package com.lightbite.healthy.account;

import com.lightbite.healthy.auth.AuthService;
import com.lightbite.healthy.common.api.ApiException;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AccountDeletionService {
    private static final Duration COOLING_OFF = Duration.ofDays(7);
    private final JdbcTemplate jdbc;
    private final AuthService auth;
    private final SecurityEventService events;
    private final Clock clock;
    @Autowired
    public AccountDeletionService(JdbcTemplate jdbc, AuthService auth, SecurityEventService events) {
        this(jdbc, auth, events, Clock.systemUTC());
    }

    AccountDeletionService(JdbcTemplate jdbc, AuthService auth, SecurityEventService events, Clock clock) {
        this.jdbc = jdbc; this.auth = auth; this.events = events; this.clock = clock;
    }

    @Transactional
    public Status request(String userId, String code) {
        Status current = pendingStatus(userId);
        if (current != null) return current;
        String phone = phone(userId);
        auth.consumeCode(phone, "ACCOUNT_DELETE", code);
        Instant now = clock.instant();
        Instant scheduled = now.plus(COOLING_OFF);
        jdbc.update("INSERT INTO account_deletion_requests (id,user_id,status,requested_at,scheduled_for) "
                        + "VALUES (?,?,'PENDING',?,?)", UUID.randomUUID().toString(), userId,
                Timestamp.from(now), Timestamp.from(scheduled));
        jdbc.update("UPDATE users SET status='DELETION_PENDING',updated_at=? WHERE id=?",
                Timestamp.from(now), userId);
        jdbc.update("UPDATE data_export_jobs SET status='CANCELLED',file_path=NULL,expires_at=NULL "
                + "WHERE user_id=? AND status IN ('PENDING','PROCESSING','READY')", userId);
        events.record(userId, "申请注销账户", null, null, "成功");
        auth.logout(userId, "", true);
        return status(now, scheduled);
    }

    public Status status(String userId) {
        Status status = pendingStatus(userId);
        if (status == null)
            throw new ApiException(HttpStatus.NOT_FOUND, "ACCOUNT_DELETION_NOT_FOUND", "没有进行中的注销申请");
        return status;
    }

    @Transactional
    public void recover(String userId, String code) {
        String phone = phone(userId);
        auth.consumeCode(phone, "ACCOUNT_RECOVER", code);
        Timestamp now = Timestamp.from(clock.instant());
        int changed = jdbc.update("UPDATE account_deletion_requests SET status='RECOVERED',recovered_at=? "
                + "WHERE user_id=? AND status='PENDING' AND scheduled_for>?", now, userId, now);
        if (changed == 0) throw new ApiException(HttpStatus.CONFLICT, "ACCOUNT_RECOVERY_EXPIRED", "账户已无法恢复");
        jdbc.update("UPDATE users SET status='ACTIVE',updated_at=? WHERE id=?", now, userId);
        events.record(userId, "恢复账户", null, null, "成功");
    }

    private String phone(String userId) {
        return jdbc.queryForObject("SELECT phone FROM users WHERE id=?", String.class, userId);
    }
    private Status pendingStatus(String userId) {
        var rows = jdbc.query("SELECT requested_at,scheduled_for FROM account_deletion_requests "
                        + "WHERE user_id=? AND status='PENDING' ORDER BY requested_at DESC LIMIT 1",
                (rs, row) -> status(rs.getTimestamp(1).toInstant(), rs.getTimestamp(2).toInstant()), userId);
        return rows.isEmpty() ? null : rows.get(0);
    }

    private Status status(Instant requestedAt, Instant scheduledFor) {
        return new Status("注销处理中", requestedAt, scheduledFor,
                Math.max(0, Duration.between(clock.instant(), scheduledFor).toSeconds()));
    }

    public record Status(String status, Instant requestedAt, Instant scheduledFor, Long remainingSeconds) {}
}
