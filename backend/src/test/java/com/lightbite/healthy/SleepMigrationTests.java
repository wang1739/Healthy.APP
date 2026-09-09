package com.lightbite.healthy;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationVersion;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;

class SleepMigrationTests {

    @Test
    void createsSleepTablesConstraintsAndIndexes() throws Exception {
        var dataSource = dataSource();
        try (var connection = dataSource.getConnection(); var statement = connection.createStatement()) {
            Flyway.configure().dataSource(dataSource).load().migrate();
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='sleep_records'"))
                    .isEqualTo(1);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM information_schema.indexes WHERE table_name='sleep_records'"))
                    .isGreaterThanOrEqualTo(3);
            statement.execute("INSERT INTO users (id,phone,status) VALUES ('u1','13000000101','ACTIVE')");
            statement.execute("INSERT INTO sleep_records (id,user_id,record_type,started_at,ended_at,timezone,"
                    + "wake_local_date,active_night_wake_date,duration_minutes,quality_score,note,source,idempotency_key) VALUES "
                    + "('s1','u1','NIGHT','2026-09-01 14:00:00','2026-09-01 22:00:00','Asia/Shanghai',"
                    + "'2026-09-02','2026-09-02',480,5,'很好','MANUAL','same')");
            statement.execute("INSERT INTO sleep_record_tags VALUES ('s1','STRESS')");
            assertThatThrownBy(() -> statement.execute("INSERT INTO sleep_record_tags VALUES ('s1','UNKNOWN')"))
                    .isInstanceOf(java.sql.SQLException.class);
            assertThatThrownBy(() -> statement.execute("UPDATE sleep_records SET quality_score=6 WHERE id='s1'"))
                    .isInstanceOf(java.sql.SQLException.class);
            assertThatThrownBy(() -> statement.execute("UPDATE sleep_records SET duration_minutes=5 WHERE id='s1'"))
                    .isInstanceOf(java.sql.SQLException.class);
            assertThatThrownBy(() -> statement.execute("INSERT INTO sleep_records (id,user_id,record_type,"
                    + "started_at,ended_at,timezone,wake_local_date,active_night_wake_date,duration_minutes,source,"
                    + "idempotency_key) VALUES ('s2','u1','NIGHT','2026-09-01 15:00:00','2026-09-01 23:00:00',"
                    + "'Asia/Shanghai','2026-09-02','2026-09-02',480,'MANUAL','other')"))
                    .isInstanceOf(java.sql.SQLException.class);
        } finally {
            dataSource.destroy();
        }
    }

    @Test
    void upgradesV7WithoutChangingExistingData() throws Exception {
        var dataSource = dataSource();
        try (var connection = dataSource.getConnection(); var statement = connection.createStatement()) {
            Flyway.configure().dataSource(dataSource).target(MigrationVersion.fromVersion("7")).load().migrate();
            statement.execute("INSERT INTO users (id,phone,status) VALUES ('u1','13000000101','ACTIVE')");
            statement.execute("INSERT INTO activity_records (id,user_id,activity_type_id,activity_name_snapshot,"
                    + "intensity,duration_minutes,occurred_at,timezone,weight_kg_snapshot,met_snapshot,"
                    + "calculation_version,estimated_kcal,final_kcal,calorie_source,source,idempotency_key) VALUES "
                    + "('a1','u1','act-walking','步行','LOW',30,CURRENT_TIMESTAMP,'UTC',60,2.5,'MET_V1',75,75,"
                    + "'ESTIMATED','MANUAL','activity')");
            Flyway.configure().dataSource(dataSource).load().migrate();
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM activity_records WHERE id='a1'")).isEqualTo(1);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM sleep_records")).isZero();
        } finally {
            dataSource.destroy();
        }
    }

    private SingleConnectionDataSource dataSource() {
        return new SingleConnectionDataSource("jdbc:h2:mem:sleep_migration_"
                + UUID.randomUUID().toString().replace("-", "")
                + ";MODE=MySQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1", "sa", "", true);
    }

    private int queryInt(java.sql.Statement statement, String sql) throws Exception {
        try (var result = statement.executeQuery(sql)) {
            result.next();
            return result.getInt(1);
        }
    }
}
