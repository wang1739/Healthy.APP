package com.lightbite.healthy.account;

import java.sql.Timestamp;
import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

@Component
public class AccountDeletionCleanup {
    private final JdbcTemplate jdbc;
    private final Clock clock;

    @Autowired
    public AccountDeletionCleanup(JdbcTemplate jdbc) {
        this(jdbc, Clock.systemUTC());
    }

    AccountDeletionCleanup(JdbcTemplate jdbc, Clock clock) {
        this.jdbc = jdbc;
        this.clock = clock;
    }

    @Scheduled(cron = "0 15 * * * *")
    public void cleanDueAccounts() {
        List<String> userIds = jdbc.queryForList("SELECT user_id FROM account_deletion_requests "
                + "WHERE status='PENDING' AND scheduled_for<=?", String.class, Timestamp.from(clock.instant()));
        userIds.forEach(this::cleanAccount);
    }

    @Transactional
    public void cleanAccount(String userId) {
        Integer due = jdbc.queryForObject("SELECT COUNT(*) FROM account_deletion_requests "
                        + "WHERE user_id=? AND status='PENDING' AND scheduled_for<=?",
                Integer.class, userId, Timestamp.from(clock.instant()));
        if (due == null || due == 0) return;

        delete("DELETE FROM health_report_sources WHERE report_id IN (SELECT id FROM health_reports WHERE user_id=?)", userId);
        delete("DELETE FROM health_reports WHERE user_id=?", userId);
        delete("DELETE FROM task_notification_events WHERE user_id=?", userId);
        delete("DELETE FROM task_operation_keys WHERE user_id=?", userId);
        delete("DELETE FROM task_instances WHERE user_id=?", userId);
        delete("DELETE FROM task_templates WHERE user_id=?", userId);
        delete("DELETE FROM task_settings WHERE user_id=?", userId);
        delete("DELETE FROM sleep_record_tags WHERE sleep_record_id IN (SELECT id FROM sleep_records WHERE user_id=?)", userId);
        delete("DELETE FROM sleep_records WHERE user_id=?", userId);
        delete("DELETE FROM activity_records WHERE user_id=?", userId);
        delete("DELETE FROM activity_types WHERE owner_user_id=?", userId);
        delete("DELETE FROM hydration_entries WHERE user_id=?", userId);
        delete("DELETE FROM hydration_settings WHERE user_id=?", userId);
        delete("DELETE FROM meal_entries WHERE user_id=?", userId);
        delete("DELETE FROM foods WHERE owner_user_id=?", userId);
        delete("DELETE FROM health_plan_versions WHERE plan_id IN (SELECT id FROM health_plans WHERE user_id=?)", userId);
        delete("DELETE FROM health_plans WHERE user_id=?", userId);
        delete("DELETE FROM body_measurements WHERE user_id=?", userId);
        delete("DELETE FROM health_goals WHERE user_id=?", userId);
        delete("DELETE FROM dietary_preferences WHERE user_id=?", userId);
        delete("DELETE FROM health_risk_answers WHERE user_id=?", userId);
        delete("DELETE FROM health_permissions WHERE user_id=?", userId);
        delete("DELETE FROM health_profiles WHERE user_id=?", userId);
        delete("DELETE FROM data_export_jobs WHERE user_id=?", userId);
        delete("DELETE FROM health_data_deletion_jobs WHERE user_id=?", userId);
        delete("DELETE FROM phone_change_appeals WHERE user_id=?", userId);
        delete("DELETE FROM consent_events WHERE user_id=?", userId);
        delete("DELETE FROM consent_records WHERE user_id=?", userId);
        delete("DELETE FROM access_tokens WHERE user_id=?", userId);
        delete("DELETE FROM refresh_tokens WHERE user_id=?", userId);
        delete("DELETE FROM user_devices WHERE user_id=?", userId);
        delete("DELETE FROM user_passwords WHERE user_id=?", userId);
        delete("DELETE FROM user_identities WHERE user_id=?", userId);

        String phone = jdbc.queryForObject("SELECT phone FROM users WHERE id=?", String.class, userId);
        delete("DELETE FROM verification_codes WHERE phone=?", phone);
        Instant now = clock.instant();
        jdbc.update("UPDATE account_deletion_requests SET status='COMPLETED',completed_at=? "
                + "WHERE user_id=? AND status='PENDING'", Timestamp.from(now), userId);
        jdbc.update("UPDATE users SET phone=?,display_name=NULL,status='DELETED',updated_at=? WHERE id=?",
                "deleted-" + UUID.randomUUID().toString().substring(0, 12), Timestamp.from(now), userId);
    }

    private void delete(String sql, Object value) {
        jdbc.update(sql, value);
    }
}
