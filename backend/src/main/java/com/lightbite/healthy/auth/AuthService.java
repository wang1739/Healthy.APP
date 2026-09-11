package com.lightbite.healthy.auth;

import com.lightbite.healthy.common.api.ApiException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.HexFormat;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AuthService {

    private static final Duration CODE_TTL = Duration.ofMinutes(5);
    private static final Duration ACCESS_TTL = Duration.ofMinutes(15);
    private static final Duration REFRESH_TTL = Duration.ofDays(30);
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final Set<String> CODE_PURPOSES = Set.of(
            "LOGIN", "DATA_EXPORT", "HEALTH_DATA_DELETE", "PHONE_OLD", "PHONE_NEW",
            "LOGOUT_OTHER_DEVICES", "ACCOUNT_DELETE", "ACCOUNT_RECOVER"
    );

    private final JdbcTemplate jdbc;
    private final PasswordEncoder passwordEncoder;
    private final boolean exposeDebugCode;

    public AuthService(
            JdbcTemplate jdbc,
            PasswordEncoder passwordEncoder,
            @Value("${app.auth.expose-debug-code:false}") boolean exposeDebugCode
    ) {
        this.jdbc = jdbc;
        this.passwordEncoder = passwordEncoder;
        this.exposeDebugCode = exposeDebugCode;
    }

    @Transactional
    public AuthDtos.SendCodeResponse sendCode(AuthDtos.SendCodeRequest request) {
        if (!CODE_PURPOSES.contains(request.purpose())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_CODE_PURPOSE", "验证码用途不正确");
        }
        Instant now = Instant.now();
        Integer recent = jdbc.queryForObject(
                "SELECT COUNT(*) FROM verification_codes WHERE phone = ? AND purpose = ? AND created_at > ?",
                Integer.class,
                request.phone(), request.purpose(), Timestamp.from(now.minusSeconds(60))
        );
        if (recent != null && recent > 0) {
            throw new ApiException(HttpStatus.TOO_MANY_REQUESTS, "CODE_TOO_FREQUENT", "请 60 秒后再获取验证码");
        }

        String code = "%06d".formatted(RANDOM.nextInt(1_000_000));
        jdbc.update("""
                        INSERT INTO verification_codes
                        (id, phone, purpose, code_hash, expires_at) VALUES (?, ?, ?, ?, ?)
                        """,
                UUID.randomUUID().toString(), request.phone(), request.purpose(), hash(code),
                Timestamp.from(now.plus(CODE_TTL))
        );
        return new AuthDtos.SendCodeResponse(
                "验证码已发送",
                CODE_TTL.toSeconds(),
                exposeDebugCode ? code : null
        );
    }

    @Transactional
    public AuthDtos.AuthResponse smsLogin(AuthDtos.SmsLoginRequest request) {
        consumeCode(request.phone(), "LOGIN", request.code());
        String userId = findOrCreateUser(request.phone());
        if (request.password() != null && !request.password().isBlank()) {
            jdbc.update("DELETE FROM user_passwords WHERE user_id = ?", userId);
            jdbc.update("INSERT INTO user_passwords (user_id, password_hash) VALUES (?, ?)",
                    userId, passwordEncoder.encode(request.password()));
        }
        jdbc.update("""
                INSERT INTO consent_records
                (id, user_id, agreement_version, privacy_version) VALUES (?, ?, '2026-09', '2026-09')
                """, UUID.randomUUID().toString(), userId);
        return issueSession(userId, createDevice(userId, request.deviceName()));
    }

    public void consumeCode(String phone, String purpose, String code) {
        Map<String, Object> savedCode;
        try {
            savedCode = jdbc.queryForMap("""
                    SELECT id, code_hash, attempts, expires_at
                    FROM verification_codes
                    WHERE phone = ? AND purpose = ? AND used_at IS NULL
                    ORDER BY created_at DESC LIMIT 1
                    """, phone, purpose);
        } catch (EmptyResultDataAccessException exception) {
            throw invalidCode();
        }

        String codeId = savedCode.get("id").toString();
        int attempts = ((Number) savedCode.get("attempts")).intValue();
        Instant expiresAt = ((Timestamp) savedCode.get("expires_at")).toInstant();
        if (attempts >= 5 || expiresAt.isBefore(Instant.now())
                || code == null || !MessageDigest.isEqual(
                savedCode.get("code_hash").toString().getBytes(StandardCharsets.US_ASCII),
                hash(code).getBytes(StandardCharsets.US_ASCII))) {
            jdbc.update("UPDATE verification_codes SET attempts = attempts + 1 WHERE id = ?", codeId);
            throw invalidCode();
        }

        jdbc.update("UPDATE verification_codes SET used_at = ? WHERE id = ?", Timestamp.from(Instant.now()), codeId);
    }

    @Transactional
    public AuthDtos.AuthResponse passwordLogin(AuthDtos.PasswordLoginRequest request) {
        Map<String, Object> account;
        try {
            account = jdbc.queryForMap("""
                    SELECT u.id, p.password_hash FROM users u
                    JOIN user_passwords p ON p.user_id = u.id
                    WHERE u.phone = ? AND u.status IN ('ACTIVE','DELETION_PENDING')
                    """, request.phone());
        } catch (EmptyResultDataAccessException exception) {
            throw invalidCredentials();
        }
        if (!passwordEncoder.matches(request.password(), account.get("password_hash").toString())) {
            throw invalidCredentials();
        }
        String userId = account.get("id").toString();
        return issueSession(userId, createDevice(userId, request.deviceName()));
    }

    @Transactional
    public AuthDtos.AuthResponse refresh(AuthDtos.RefreshRequest request) {
        Map<String, Object> token;
        try {
            token = jdbc.queryForMap("""
                    SELECT id, user_id, device_id, expires_at FROM refresh_tokens
                    WHERE token_hash = ? AND revoked_at IS NULL
                    """, hash(request.refreshToken()));
        } catch (EmptyResultDataAccessException exception) {
            throw invalidRefreshToken();
        }
        if (((Timestamp) token.get("expires_at")).toInstant().isBefore(Instant.now())) {
            throw invalidRefreshToken();
        }
        jdbc.update("UPDATE refresh_tokens SET revoked_at = ? WHERE id = ?",
                Timestamp.from(Instant.now()), token.get("id"));
        return issueSession(token.get("user_id").toString(), token.get("device_id").toString());
    }

    @Transactional
    public void logout(String userId, String accessToken, boolean allDevices) {
        Instant now = Instant.now();
        if (allDevices) {
            jdbc.update("UPDATE user_devices SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL",
                    Timestamp.from(now), userId);
            jdbc.update("UPDATE access_tokens SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL",
                    Timestamp.from(now), userId);
            jdbc.update("UPDATE refresh_tokens SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL",
                    Timestamp.from(now), userId);
            return;
        }
        String deviceId = validateAccessToken(accessToken).deviceId();
        revokeDevice(userId, deviceId);
    }

    @Transactional
    public void revokeDevice(String userId, String deviceId) {
        Instant now = Instant.now();
        int owned = jdbc.update("""
                UPDATE user_devices SET revoked_at = ?
                WHERE id = ? AND user_id = ? AND revoked_at IS NULL
                """, Timestamp.from(now), deviceId, userId);
        if (owned == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "DEVICE_NOT_FOUND", "设备不存在");
        }
        jdbc.update("UPDATE access_tokens SET revoked_at = ? WHERE device_id = ? AND revoked_at IS NULL",
                Timestamp.from(now), deviceId);
        jdbc.update("UPDATE refresh_tokens SET revoked_at = ? WHERE device_id = ? AND revoked_at IS NULL",
                Timestamp.from(now), deviceId);
    }

    @Transactional
    public void revokeOtherDevices(String userId, String currentDeviceId) {
        Instant now = Instant.now();
        jdbc.update("UPDATE user_devices SET revoked_at=? WHERE user_id=? AND id<>? AND revoked_at IS NULL",
                Timestamp.from(now), userId, currentDeviceId);
        jdbc.update("UPDATE access_tokens SET revoked_at=? WHERE user_id=? AND device_id<>? AND revoked_at IS NULL",
                Timestamp.from(now), userId, currentDeviceId);
        jdbc.update("UPDATE refresh_tokens SET revoked_at=? WHERE user_id=? AND device_id<>? AND revoked_at IS NULL",
                Timestamp.from(now), userId, currentDeviceId);
    }

    public String currentDeviceId(String accessToken) {
        SessionIdentity identity = validateAccessToken(accessToken);
        if (identity == null) throw invalidRefreshToken();
        return identity.deviceId();
    }

    public SessionIdentity validateAccessToken(String token) {
        try {
            Map<String, Object> result = jdbc.queryForMap("""
                    SELECT t.user_id, t.device_id, t.expires_at, u.status
                    FROM access_tokens t
                    JOIN users u ON u.id = t.user_id
                    JOIN user_devices d ON d.id = t.device_id
                    WHERE t.token_hash = ? AND t.revoked_at IS NULL
                      AND d.revoked_at IS NULL AND u.status IN ('ACTIVE','DELETION_PENDING')
                    """, hash(token));
            if (((Timestamp) result.get("expires_at")).toInstant().isBefore(Instant.now())) {
                return null;
            }
            return new SessionIdentity(result.get("user_id").toString(), result.get("device_id").toString(),
                    result.get("status").toString());
        } catch (EmptyResultDataAccessException exception) {
            return null;
        }
    }

    private String findOrCreateUser(String phone) {
        try {
            return jdbc.queryForObject("SELECT id FROM users WHERE phone = ?", String.class, phone);
        } catch (EmptyResultDataAccessException exception) {
            String id = UUID.randomUUID().toString();
            jdbc.update("INSERT INTO users (id, phone) VALUES (?, ?)", id, phone);
            jdbc.update("""
                    INSERT INTO user_identities (id, user_id, provider, provider_subject)
                    VALUES (?, ?, 'PHONE', ?)
                    """, UUID.randomUUID().toString(), id, phone);
            return id;
        }
    }

    private String createDevice(String userId, String name) {
        String id = UUID.randomUUID().toString();
        jdbc.update("INSERT INTO user_devices (id, user_id, name) VALUES (?, ?, ?)", id, userId, name);
        return id;
    }

    private AuthDtos.AuthResponse issueSession(String userId, String deviceId) {
        Instant now = Instant.now();
        String accessToken = randomToken();
        String refreshToken = randomToken();
        jdbc.update("""
                INSERT INTO access_tokens
                (id, user_id, device_id, token_hash, expires_at) VALUES (?, ?, ?, ?, ?)
                """, UUID.randomUUID().toString(), userId, deviceId, hash(accessToken),
                Timestamp.from(now.plus(ACCESS_TTL)));
        jdbc.update("""
                INSERT INTO refresh_tokens
                (id, user_id, device_id, token_hash, expires_at) VALUES (?, ?, ?, ?, ?)
                """, UUID.randomUUID().toString(), userId, deviceId, hash(refreshToken),
                Timestamp.from(now.plus(REFRESH_TTL)));
        Map<String, Object> account = jdbc.queryForMap("SELECT status,phone FROM users WHERE id=?", userId);
        return new AuthDtos.AuthResponse(accessToken, refreshToken, ACCESS_TTL.toSeconds(),
                isProfileComplete(userId), account.get("status").toString(), account.get("phone").toString());
    }

    private boolean isProfileComplete(String userId) {
        Integer count = jdbc.queryForObject(
                """
                SELECT COUNT(*) FROM health_profiles
                WHERE user_id = ? AND completed = TRUE AND metabolic_basis IS NOT NULL
                """,
                Integer.class, userId);
        return count != null && count > 0;
    }

    private String randomToken() {
        byte[] bytes = new byte[32];
        RANDOM.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private String hash(String value) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException(exception);
        }
    }

    private ApiException invalidCode() {
        return new ApiException(HttpStatus.UNAUTHORIZED, "INVALID_VERIFICATION_CODE", "验证码错误或已过期");
    }

    private ApiException invalidCredentials() {
        return new ApiException(HttpStatus.UNAUTHORIZED, "INVALID_CREDENTIALS", "手机号或密码错误");
    }

    private ApiException invalidRefreshToken() {
        return new ApiException(HttpStatus.UNAUTHORIZED, "INVALID_REFRESH_TOKEN", "登录状态已失效，请重新登录");
    }

    public record SessionIdentity(String userId, String deviceId, String accountStatus) {
    }
}
