package com.lightbite.healthy;

import org.springframework.jdbc.core.JdbcTemplate;

final class TestHealthAuthorization {
    private TestHealthAuthorization() {}

    static void grant(JdbcTemplate jdbc, String userId) {
        jdbc.update("""
                MERGE INTO health_permissions
                (user_id, health_data_authorized, authorization_version, updated_at)
                KEY(user_id) VALUES (?, TRUE, '2026-09', CURRENT_TIMESTAMP)
                """, userId);
    }
}
