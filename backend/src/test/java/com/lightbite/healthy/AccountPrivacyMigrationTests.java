package com.lightbite.healthy;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationVersion;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;

class AccountPrivacyMigrationTests {

    @Test
    void upgradesV11AndKeepsExistingAccountData() throws Exception {
        var dataSource = dataSource();
        try (var connection = dataSource.getConnection(); var statement = connection.createStatement()) {
            Flyway.configure().dataSource(dataSource).target(MigrationVersion.fromVersion("11")).load().migrate();
            statement.execute("INSERT INTO users (id,phone,status) VALUES ('u1','13000000981','ACTIVE')");
            statement.execute("INSERT INTO user_devices (id,user_id,name) VALUES ('d1','u1','Android 手机')");
            statement.execute("INSERT INTO consent_records (id,user_id,agreement_version,privacy_version) "
                    + "VALUES ('c1','u1','2026-09','2026-09')");
            statement.execute("INSERT INTO health_permissions "
                    + "(user_id,health_data_authorized,authorization_version) VALUES ('u1',TRUE,'2026-09')");

            Flyway.configure().dataSource(dataSource).load().migrate();

            assertThat(count(statement, "users", "id='u1'")).isEqualTo(1);
            assertThat(count(statement, "user_devices", "id='d1'")).isEqualTo(1);
            assertThat(count(statement, "consent_events", "user_id='u1'")).isEqualTo(2);
            assertThat(count(statement, "privacy_documents", "1=1")).isEqualTo(2);
        } finally {
            dataSource.destroy();
        }
    }

    @Test
    void createsAccountPrivacyTablesAndIndexesFromEmptyDatabase() throws Exception {
        var dataSource = dataSource();
        try (var connection = dataSource.getConnection(); var statement = connection.createStatement()) {
            Flyway.configure().dataSource(dataSource).load().migrate();

            assertThat(count(statement, "information_schema.tables",
                    "table_name IN ('privacy_documents','consent_events','security_events','data_export_jobs',"
                            + "'health_data_deletion_jobs','phone_change_appeals')"))
                    .isEqualTo(6);
            assertThat(count(statement, "information_schema.indexes",
                    "table_name IN ('consent_events','security_events','data_export_jobs',"
                            + "'health_data_deletion_jobs','phone_change_appeals')"))
                    .isGreaterThanOrEqualTo(6);
            assertThat(count(statement, "privacy_documents", "document_type='PRIVACY_POLICY'"))
                    .isEqualTo(1);
        } finally {
            dataSource.destroy();
        }
    }

    private SingleConnectionDataSource dataSource() {
        return new SingleConnectionDataSource("jdbc:h2:mem:account_privacy_migration_"
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
