package com.lightbite.healthy.account;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

@Service
public class SecurityEventService {
    private final JdbcTemplate jdbc;
    public SecurityEventService(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    public void record(String userId, String type, String deviceId, String deviceName, String result) {
        jdbc.update("INSERT INTO security_events (id,user_id,event_type,device_id,device_name,result) VALUES (?,?,?,?,?,?)",
                UUID.randomUUID().toString(), userId, type, deviceId, deviceName, result);
    }

    public List<AccountDtos.SecurityEventResponse> list(String userId) {
        return jdbc.query("SELECT event_type,device_name,result,created_at FROM security_events "
                        + "WHERE user_id=? ORDER BY created_at DESC LIMIT 100",
                (rs, row) -> new AccountDtos.SecurityEventResponse(rs.getString(1), rs.getString(2),
                        rs.getString(3), instant(rs.getTimestamp(4))), userId);
    }

    private Instant instant(Timestamp value) { return value == null ? null : value.toInstant(); }
}
