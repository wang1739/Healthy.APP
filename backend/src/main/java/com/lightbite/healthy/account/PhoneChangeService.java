package com.lightbite.healthy.account;

import com.lightbite.healthy.auth.AuthService;
import com.lightbite.healthy.common.api.ApiException;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class PhoneChangeService {
    private final JdbcTemplate jdbc;
    private final AuthService auth;
    private final SecurityEventService events;
    public PhoneChangeService(JdbcTemplate jdbc, AuthService auth, SecurityEventService events) {
        this.jdbc = jdbc; this.auth = auth; this.events = events;
    }

    @Transactional
    public void change(String userId, String currentDeviceId, PhoneChangeDtos.ChangeRequest request) {
        String oldPhone = phone(userId);
        auth.consumeCode(oldPhone, "PHONE_OLD", request.oldCode());
        auth.consumeCode(request.newPhone(), "PHONE_NEW", request.newCode());
        Integer used = jdbc.queryForObject("SELECT COUNT(*) FROM users WHERE phone=? AND id<>? AND status<>'DELETED'",
                Integer.class, request.newPhone(), userId);
        if (used != null && used > 0)
            throw new ApiException(HttpStatus.CONFLICT, "PHONE_IN_USE", "该手机号已绑定其他账户");
        jdbc.update("UPDATE users SET phone=?,updated_at=CURRENT_TIMESTAMP WHERE id=?", request.newPhone(), userId);
        jdbc.update("UPDATE user_identities SET provider_subject=? WHERE user_id=? AND provider='PHONE'",
                request.newPhone(), userId);
        auth.revokeOtherDevices(userId, currentDeviceId);
        events.record(userId, "更换手机号", currentDeviceId, null, "成功");
    }

    @Transactional
    public PhoneChangeDtos.AppealResponse appeal(String userId, PhoneChangeDtos.AppealRequest request) {
        Integer active = jdbc.queryForObject("SELECT COUNT(*) FROM phone_change_appeals WHERE user_id=? "
                + "AND status IN ('PENDING','PROCESSING')", Integer.class, userId);
        if (active != null && active > 0)
            throw new ApiException(HttpStatus.CONFLICT, "PHONE_APPEAL_ACTIVE", "已有手机号申诉正在处理");
        String id = UUID.randomUUID().toString();
        jdbc.update("INSERT INTO phone_change_appeals "
                        + "(id,user_id,new_phone,status,material_reference) VALUES (?,?,?,'PENDING',?)",
                id, userId, request.newPhone(), request.materialReference());
        events.record(userId, "提交手机号申诉", null, null, "成功");
        return appeals(userId).stream().filter(value -> id.equals(value.id())).findFirst().orElseThrow();
    }

    public List<PhoneChangeDtos.AppealResponse> appeals(String userId) {
        return jdbc.query("SELECT id,new_phone,status,result_reason,created_at,completed_at FROM phone_change_appeals "
                        + "WHERE user_id=? ORDER BY created_at DESC",
                (rs, row) -> new PhoneChangeDtos.AppealResponse(rs.getString(1), mask(rs.getString(2)), rs.getString(3),
                        rs.getString(4), rs.getTimestamp(5).toInstant(), instant(rs.getTimestamp(6))), userId);
    }

    public boolean hasActiveAppeal(String userId) {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM phone_change_appeals WHERE user_id=? "
                + "AND status IN ('PENDING','PROCESSING')", Integer.class, userId);
        return count != null && count > 0;
    }

    private String phone(String userId) { return jdbc.queryForObject("SELECT phone FROM users WHERE id=?", String.class, userId); }
    private String mask(String phone) { return phone.substring(0, 3) + "****" + phone.substring(7); }
    private Instant instant(Timestamp value) { return value == null ? null : value.toInstant(); }
}
