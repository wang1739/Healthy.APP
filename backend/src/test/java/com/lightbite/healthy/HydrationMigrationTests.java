package com.lightbite.healthy;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationVersion;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;

class HydrationMigrationTests {

    @Test
    void migratesEmptyDatabaseWithHydrationConstraintsAndIndexes() throws Exception {
        String url = databaseUrl();
        var dataSource = new SingleConnectionDataSource(url, "sa", "", true);
        try (var connection = dataSource.getConnection()) {
            Flyway.configure().dataSource(dataSource).load().migrate();
            try (var statement = connection.createStatement()) {
            assertThat(tableCount(statement, "hydration_settings")).isEqualTo(1);
            assertThat(tableCount(statement, "hydration_entries")).isEqualTo(1);
            assertThat(indexCount(statement, "hydration_entries")).isGreaterThanOrEqualTo(3);
            statement.execute("INSERT INTO users (id,phone,status) VALUES ('u1','13000000001','ACTIVE')");
            statement.execute("INSERT INTO hydration_settings (user_id) VALUES ('u1')");
            statement.execute("INSERT INTO hydration_entries "
                    + "(id,user_id,amount_ml,occurred_at,timezone,source,idempotency_key) "
                    + "VALUES ('e1','u1',250,CURRENT_TIMESTAMP,'Asia/Shanghai','QUICK','key')");

            assertThatThrownBy(() -> statement.execute(
                    "INSERT INTO hydration_settings (user_id) VALUES ('u1')"))
                    .isInstanceOf(java.sql.SQLException.class);
            assertThatThrownBy(() -> statement.execute("INSERT INTO hydration_entries "
                    + "(id,user_id,amount_ml,occurred_at,timezone,source,idempotency_key) "
                    + "VALUES ('e2','u1',250,CURRENT_TIMESTAMP,'Asia/Shanghai','QUICK','key')"))
                    .isInstanceOf(java.sql.SQLException.class);
            assertThatThrownBy(() -> statement.execute("UPDATE hydration_entries SET amount_ml=3001 WHERE id='e1'"))
                    .isInstanceOf(java.sql.SQLException.class);
            assertThatThrownBy(() -> statement.execute("UPDATE hydration_settings SET daily_target_ml=525 WHERE user_id='u1'"))
                    .isInstanceOf(java.sql.SQLException.class);
            assertThatThrownBy(() -> statement.execute("UPDATE hydration_settings SET default_cup_ml=49 WHERE user_id='u1'"))
                    .isInstanceOf(java.sql.SQLException.class);
            assertThatThrownBy(() -> statement.execute("UPDATE hydration_settings SET reminder_interval_minutes=0 WHERE user_id='u1'"))
                    .isInstanceOf(java.sql.SQLException.class);
            assertThatThrownBy(() -> statement.execute("UPDATE hydration_settings SET version=0 WHERE user_id='u1'"))
                    .isInstanceOf(java.sql.SQLException.class);
            }
        } finally {
            dataSource.destroy();
        }
    }

    @Test
    void upgradesV5WithoutChangingExistingDomainData() throws Exception {
        String url = databaseUrl();
        var dataSource = new SingleConnectionDataSource(url, "sa", "", true);
        try (var connection = dataSource.getConnection()) {
            Flyway.configure().dataSource(dataSource)
                    .target(MigrationVersion.fromVersion("5")).load().migrate();
            try (var statement = connection.createStatement()) {
            statement.execute("INSERT INTO users (id,phone,status) VALUES ('u1','13000000001','ACTIVE')");
            statement.execute("INSERT INTO health_profiles (user_id,current_step,completed) VALUES ('u1',7,TRUE)");
            statement.execute("INSERT INTO health_plans "
                    + "(id,user_id,status,phase_start_date,phase_end_date,current_version) "
                    + "VALUES ('p1','u1','ACTIVE','2026-09-01','2026-09-28',1)");
            statement.execute("INSERT INTO meal_entries "
                    + "(id,user_id,entry_date,meal_type,food_name_snapshot,grams,calories_snapshot,"
                    + "protein_snapshot,carbs_snapshot,fat_snapshot,idempotency_key) "
                    + "VALUES ('m1','u1','2026-09-08','LUNCH','米饭',150,174,3.9,38.85,.45,'meal-key')");
            }
            Flyway.configure().dataSource(dataSource).load().migrate();
            try (var statement = connection.createStatement()) {
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM users WHERE id='u1' AND status='ACTIVE'"))
                    .isEqualTo(1);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM health_profiles WHERE user_id='u1' AND completed=TRUE"))
                    .isEqualTo(1);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM health_plans WHERE id='p1' AND status='ACTIVE'"))
                    .isEqualTo(1);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM foods WHERE name='米饭'"))
                    .isEqualTo(1);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM meal_entries WHERE id='m1' AND deleted_at IS NULL"))
                    .isEqualTo(1);
            }
        } finally {
            dataSource.destroy();
        }
    }

    private String databaseUrl() {
        return "jdbc:h2:mem:hydration_migration_" + UUID.randomUUID().toString().replace("-", "")
                + ";MODE=MySQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1";
    }

    private int tableCount(java.sql.Statement statement, String table) throws Exception {
        return queryInt(statement, "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='" + table + "'");
    }

    private int indexCount(java.sql.Statement statement, String table) throws Exception {
        return queryInt(statement, "SELECT COUNT(*) FROM information_schema.indexes WHERE table_name='" + table + "'");
    }

    private int queryInt(java.sql.Statement statement, String sql) throws Exception {
        try (var result = statement.executeQuery(sql)) {
            result.next();
            return result.getInt(1);
        }
    }
}
