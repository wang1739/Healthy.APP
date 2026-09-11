package com.lightbite.healthy.account;

import com.lightbite.healthy.auth.AuthService;
import com.lightbite.healthy.common.api.ApiException;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AccountService {
    private final JdbcTemplate jdbc;
    private final AuthService auth;
    private final SecurityEventService events;
    public AccountService(JdbcTemplate jdbc, AuthService auth, SecurityEventService events) {
        this.jdbc = jdbc; this.auth = auth; this.events = events;
    }

    public AccountDtos.AccountResponse account(String userId) {
        Map<String, Object> user = jdbc.queryForMap("SELECT phone,display_name,status FROM users WHERE id=?", userId);
        String phone = user.get("phone").toString();
        return new AccountDtos.AccountResponse(phone, mask(phone),
                user.get("display_name") == null ? null : user.get("display_name").toString(),
                user.get("status").toString(),
                exists("SELECT COUNT(*) FROM health_profiles WHERE user_id=? AND completed=TRUE "
                        + "AND metabolic_basis IS NOT NULL", userId),
                exists("SELECT COUNT(*) FROM health_permissions WHERE user_id=? AND health_data_authorized=TRUE", userId));
    }

    public List<AccountDtos.DeviceResponse> devices(String userId, String currentDeviceId) {
        return jdbc.query("SELECT id,name,system_name,last_seen_at,created_at FROM user_devices "
                        + "WHERE user_id=? AND revoked_at IS NULL ORDER BY created_at DESC",
                (rs, row) -> new AccountDtos.DeviceResponse(rs.getString(1), rs.getString(2), rs.getString(3),
                        instant(rs.getTimestamp(4)), instant(rs.getTimestamp(5)), currentDeviceId.equals(rs.getString(1))),
                userId);
    }

    @Transactional
    public void revoke(String userId, String currentDeviceId, String targetDeviceId) {
        if (currentDeviceId.equals(targetDeviceId))
            throw new ApiException(HttpStatus.CONFLICT, "CURRENT_DEVICE", "当前设备请使用退出登录");
        String name = deviceName(userId, targetDeviceId);
        auth.revokeDevice(userId, targetDeviceId);
        events.record(userId, "移除设备", currentDeviceId, name, "成功");
    }

    @Transactional
    public void revokeOthers(String userId, String currentDeviceId, String code) {
        String phone = jdbc.queryForObject("SELECT phone FROM users WHERE id=?", String.class, userId);
        auth.consumeCode(phone, "LOGOUT_OTHER_DEVICES", code);
        auth.revokeOtherDevices(userId, currentDeviceId);
        events.record(userId, "退出其他所有设备", currentDeviceId, deviceName(userId, currentDeviceId), "成功");
    }

    private String deviceName(String userId, String deviceId) {
        List<String> values = jdbc.query("SELECT name FROM user_devices WHERE user_id=? AND id=?",
                (rs, row) -> rs.getString(1), userId, deviceId);
        if (values.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "DEVICE_NOT_FOUND", "设备不存在");
        return values.get(0);
    }
    private boolean exists(String sql, String userId) {
        Integer count = jdbc.queryForObject(sql, Integer.class, userId); return count != null && count > 0;
    }
    private String mask(String phone) {
        return phone.length() < 7 ? "***" : phone.substring(0, 3) + "****" + phone.substring(phone.length() - 4);
    }
    private Instant instant(Timestamp value) { return value == null ? null : value.toInstant(); }
}
