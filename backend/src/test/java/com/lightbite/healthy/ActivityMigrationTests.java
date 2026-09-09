package com.lightbite.healthy;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationVersion;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;

class ActivityMigrationTests {

    @Test
    void migratesEmptyDatabaseWithSeedDataConstraintsAndIndexes() throws Exception {
        var dataSource = dataSource();
        try (var connection = dataSource.getConnection(); var statement = connection.createStatement()) {
            Flyway.configure().dataSource(dataSource).load().migrate();

            assertThat(queryInt(statement, "SELECT COUNT(*) FROM activity_types WHERE type_scope='SYSTEM'"))
                    .isEqualTo(14);
            assertThat(queryInt(statement,
                    "SELECT COUNT(*) FROM information_schema.indexes WHERE table_name='activity_records'"))
                    .isGreaterThanOrEqualTo(3);
            statement.execute("INSERT INTO users (id,phone,status) VALUES ('u1','13000000001','ACTIVE')");
            statement.execute("INSERT INTO activity_records "
                    + "(id,user_id,activity_type_id,activity_name_snapshot,intensity,duration_minutes,"
                    + "occurred_at,timezone,weight_kg_snapshot,met_snapshot,calculation_version,"
                    + "estimated_kcal,final_kcal,calorie_source,source,idempotency_key) "
                    + "VALUES ('r1','u1','act-walking','步行','LOW',30,CURRENT_TIMESTAMP,'Asia/Shanghai',"
                    + "60,2.5,'MET_V1',75,75,'ESTIMATED','MANUAL','same')");

            assertThatThrownBy(() -> statement.execute("INSERT INTO activity_records "
                    + "(id,user_id,activity_type_id,activity_name_snapshot,intensity,duration_minutes,"
                    + "occurred_at,timezone,weight_kg_snapshot,met_snapshot,calculation_version,"
                    + "estimated_kcal,final_kcal,calorie_source,source,idempotency_key) "
                    + "VALUES ('r2','u1','act-walking','步行','LOW',30,CURRENT_TIMESTAMP,'UTC',"
                    + "60,2.5,'MET_V1',75,75,'ESTIMATED','MANUAL','same')"))
                    .isInstanceOf(java.sql.SQLException.class);
            assertThatThrownBy(() -> statement.execute(
                    "UPDATE activity_records SET duration_minutes=0 WHERE id='r1'"))
                    .isInstanceOf(java.sql.SQLException.class);
            assertThatThrownBy(() -> statement.execute(
                    "UPDATE activity_records SET final_kcal=10001 WHERE id='r1'"))
                    .isInstanceOf(java.sql.SQLException.class);
        } finally {
            dataSource.destroy();
        }
    }

    @Test
    void upgradesV6WithoutChangingExistingDomainData() throws Exception {
        var dataSource = dataSource();
        try (var connection = dataSource.getConnection(); var statement = connection.createStatement()) {
            Flyway.configure().dataSource(dataSource).target(MigrationVersion.fromVersion("6")).load().migrate();
            statement.execute("INSERT INTO users (id,phone,status) VALUES ('u1','13000000001','ACTIVE')");
            statement.execute("INSERT INTO health_profiles (user_id,current_step,completed) VALUES ('u1',7,TRUE)");
            statement.execute("INSERT INTO hydration_entries "
                    + "(id,user_id,amount_ml,occurred_at,timezone,source,idempotency_key) "
                    + "VALUES ('h1','u1',250,CURRENT_TIMESTAMP,'Asia/Shanghai','QUICK','water')");

            Flyway.configure().dataSource(dataSource).load().migrate();

            assertThat(queryInt(statement, "SELECT COUNT(*) FROM users WHERE id='u1'")).isEqualTo(1);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM health_profiles WHERE user_id='u1'"))
                    .isEqualTo(1);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM hydration_entries WHERE id='h1'"))
                    .isEqualTo(1);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM activity_types")).isEqualTo(14);
        } finally {
            dataSource.destroy();
        }
    }

    private SingleConnectionDataSource dataSource() {
        String url = "jdbc:h2:mem:activity_migration_" + UUID.randomUUID().toString().replace("-", "")
                + ";MODE=MySQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1";
        return new SingleConnectionDataSource(url, "sa", "", true);
    }

    private int queryInt(java.sql.Statement statement, String sql) throws Exception {
        try (var result = statement.executeQuery(sql)) {
            result.next();
            return result.getInt(1);
        }
    }
}
