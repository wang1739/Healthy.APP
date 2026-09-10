package com.lightbite.healthy;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationVersion;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;

class ReportMigrationTests {

    @Test
    void upgradesV10ToV11WithoutChangingExistingData() throws Exception {
        var dataSource = dataSource();
        try (var connection = dataSource.getConnection(); var statement = connection.createStatement()) {
            Flyway.configure().dataSource(dataSource).target(MigrationVersion.fromVersion("10")).load().migrate();
            statement.execute("INSERT INTO users (id,phone,status) VALUES ('u1','13000000951','ACTIVE')");
            statement.execute("INSERT INTO health_profiles (user_id,current_step,completed) VALUES ('u1',7,TRUE)");
            statement.execute("INSERT INTO task_settings (user_id) VALUES ('u1')");
            Flyway.configure().dataSource(dataSource).load().migrate();
            assertThat(count(statement, "users", "id='u1'")).isEqualTo(1);
            assertThat(count(statement, "health_profiles", "user_id='u1'")).isEqualTo(1);
            assertThat(count(statement, "task_settings", "user_id='u1'")).isEqualTo(1);
        } finally {
            dataSource.destroy();
        }
    }

    @Test
    void createsReportTablesConstraintsAndIndexesFromEmptyDatabase() throws Exception {
        var dataSource = dataSource();
        try (var connection = dataSource.getConnection(); var statement = connection.createStatement()) {
            Flyway.configure().dataSource(dataSource).load().migrate();
            statement.execute("INSERT INTO users (id,phone,status) VALUES ('u1','13000000952','ACTIVE')");
            statement.execute("INSERT INTO health_reports (id,user_id,report_type,period_start,period_end,timezone,"
                    + "period_status,version,rules_version,data_cutoff_at,input_hash,snapshot_json,idempotency_key) "
                    + "VALUES ('r1','u1','DAILY','2026-09-10','2026-09-10','Asia/Shanghai','COMPLETE',1,"
                    + "'REPORT_RULES_V1',CURRENT_TIMESTAMP,'" + "a".repeat(64) + "','{}','key-1')");
            statement.execute("INSERT INTO health_report_sources "
                    + "(report_id,section_code,metric_code,source_type,source_id,source_local_date,location_label) "
                    + "VALUES ('r1','NUTRITION','CALORIES','MEAL_ENTRY','m1','2026-09-10','2026年9月10日饮食记录')");
            assertThatThrownBy(() -> statement.execute("INSERT INTO health_reports "
                    + "(id,user_id,report_type,period_start,period_end,timezone,period_status,version,rules_version,"
                    + "data_cutoff_at,input_hash,snapshot_json,idempotency_key) VALUES "
                    + "('r2','u1','DAILY','2026-09-10','2026-09-10','UTC','COMPLETE',1,'REPORT_RULES_V1',"
                    + "CURRENT_TIMESTAMP,'" + "b".repeat(64) + "','{}','key-2')"))
                    .isInstanceOf(java.sql.SQLException.class);
            assertThatThrownBy(() -> statement.execute("UPDATE health_reports SET report_type='YEARLY' WHERE id='r1'"))
                    .isInstanceOf(java.sql.SQLException.class);
            assertThat(count(statement, "information_schema.indexes",
                    "table_name IN ('health_reports','health_report_sources')")).isGreaterThanOrEqualTo(5);
        } finally {
            dataSource.destroy();
        }
    }

    private SingleConnectionDataSource dataSource() {
        return new SingleConnectionDataSource("jdbc:h2:mem:report_migration_"
                + UUID.randomUUID().toString().replace("-", "")
                + ";MODE=MySQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1", "sa", "", true);
    }

    private int count(java.sql.Statement statement, String table, String condition) throws Exception {
        try (var result = statement.executeQuery("SELECT COUNT(*) FROM " + table + " WHERE " + condition)) {
            result.next();
            return result.getInt(1);
        }
    }
}
