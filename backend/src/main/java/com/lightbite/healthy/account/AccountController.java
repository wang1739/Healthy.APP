package com.lightbite.healthy.account;

import com.lightbite.healthy.auth.AuthService;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/account")
public class AccountController {

    private final JdbcTemplate jdbc;
    private final AuthService authService;

    public AccountController(JdbcTemplate jdbc, AuthService authService) {
        this.jdbc = jdbc;
        this.authService = authService;
    }

    @GetMapping
    AccountResponse account(Authentication authentication) {
        Map<String, Object> user = jdbc.queryForMap("""
                SELECT id, phone, display_name FROM users WHERE id = ?
                """, authentication.getName());
        boolean profileComplete = Boolean.TRUE.equals(jdbc.queryForObject(
                """
                SELECT EXISTS(SELECT 1 FROM health_profiles
                WHERE user_id = ? AND completed = TRUE AND metabolic_basis IS NOT NULL)
                """,
                Boolean.class,
                authentication.getName()
        ));
        return new AccountResponse(
                user.get("id").toString(),
                user.get("phone").toString(),
                user.get("display_name") == null ? null : user.get("display_name").toString(),
                profileComplete
        );
    }

    @GetMapping("/devices")
    List<DeviceResponse> devices(Authentication authentication) {
        return jdbc.query("""
                SELECT id, name, last_seen_at, created_at FROM user_devices
                WHERE user_id = ? AND revoked_at IS NULL ORDER BY created_at DESC
                """, (resultSet, row) -> new DeviceResponse(
                resultSet.getString("id"),
                resultSet.getString("name"),
                toInstant(resultSet.getTimestamp("last_seen_at")),
                toInstant(resultSet.getTimestamp("created_at"))
        ), authentication.getName());
    }

    @DeleteMapping("/devices/{id}")
    void revokeDevice(@PathVariable String id, Authentication authentication) {
        authService.revokeDevice(authentication.getName(), id);
    }

    private Instant toInstant(Timestamp timestamp) {
        return timestamp.toInstant();
    }

    record AccountResponse(String id, String phone, String displayName, boolean profileComplete) {
    }

    record DeviceResponse(String id, String name, Instant lastSeenAt, Instant createdAt) {
    }
}
