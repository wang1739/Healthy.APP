package com.lightbite.healthy;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationVersion;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;

class TaskMigrationTests {

    @Test
    void upgradesV8ToV9WithoutChangingExistingData() throws Exception {
        var dataSource = dataSource();
        try (var connection = dataSource.getConnection(); var statement = connection.createStatement()) {
            Flyway.configure().dataSource(dataSource).target(MigrationVersion.fromVersion("8")).load().migrate();
            statement.execute("INSERT INTO users (id,phone,status) VALUES ('u1','13000000901','ACTIVE')");
            statement.execute("INSERT INTO health_profiles (user_id) VALUES ('u1')");
            statement.execute("INSERT INTO health_plans (id,user_id,status,phase_start_date,phase_end_date,current_version) "
                    + "VALUES ('p1','u1','ACTIVE','2026-09-01','2026-12-31',1)");
            statement.execute("INSERT INTO meal_entries (id,user_id,entry_date,meal_type,food_name_snapshot,grams,"
                    + "calories_snapshot,protein_snapshot,carbs_snapshot,fat_snapshot,idempotency_key) VALUES "
                    + "('m1','u1','2026-09-09','BREAKFAST','米饭',100,116,2.6,25.9,.3,'meal-key')");
            statement.execute("INSERT INTO hydration_entries (id,user_id,amount_ml,occurred_at,timezone,source,"
                    + "idempotency_key) VALUES ('h1','u1',250,'2026-09-09 08:00:00','UTC','QUICK','water-key')");
            statement.execute("INSERT INTO activity_records (id,user_id,activity_type_id,activity_name_snapshot,"
                    + "intensity,duration_minutes,occurred_at,timezone,weight_kg_snapshot,met_snapshot,"
                    + "calculation_version,estimated_kcal,final_kcal,calorie_source,source,idempotency_key) VALUES "
                    + "('a1','u1','act-walking','步行','MEDIUM',30,'2026-09-09 08:00:00','UTC',60,3.5,"
                    + "'MET_V1',100,100,'ESTIMATED','MANUAL','activity-key')");
            statement.execute("INSERT INTO sleep_records (id,user_id,record_type,started_at,ended_at,timezone,"
                    + "wake_local_date,active_night_wake_date,duration_minutes,source,idempotency_key) VALUES "
                    + "('s1','u1','NIGHT','2026-09-08 14:00:00','2026-09-08 22:00:00','UTC',"
                    + "'2026-09-09','2026-09-09',480,'MANUAL','sleep-key')");
            Flyway.configure().dataSource(dataSource).target(MigrationVersion.fromVersion("9")).load().migrate();
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM users WHERE id='u1'")).isEqualTo(1);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM health_profiles WHERE user_id='u1'")).isEqualTo(1);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM health_plans WHERE id='p1'")).isEqualTo(1);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM meal_entries WHERE id='m1'")).isEqualTo(1);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM hydration_entries WHERE id='h1'")).isEqualTo(1);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM activity_records WHERE id='a1'")).isEqualTo(1);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM sleep_records WHERE id='s1'")).isEqualTo(1);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM information_schema.tables "
                    + "WHERE table_name IN ('task_templates','task_instances')")).isEqualTo(2);
        } finally {
            dataSource.destroy();
        }
    }

    @Test
    void createsCoreConstraintsAndIndexes() throws Exception {
        var dataSource = dataSource();
        try (var connection = dataSource.getConnection(); var statement = connection.createStatement()) {
            Flyway.configure().dataSource(dataSource).target(MigrationVersion.fromVersion("9")).load().migrate();
            statement.execute("INSERT INTO users (id,phone,status) VALUES ('u1','13000000902','ACTIVE')");
            statement.execute("INSERT INTO task_templates "
                    + "(id,user_id,source,title,category,priority,all_day,recurrence_type,effective_from,version,idempotency_key) "
                    + "VALUES ('t1','u1','USER','晨间整理','LIFE','NORMAL',TRUE,'DAILY','2026-09-10',0,'create-1')");
            statement.execute("INSERT INTO task_instances "
                    + "(id,user_id,template_id,original_local_date,current_local_date,timezone,status,title,category,"
                    + "priority,all_day,postpone_count,version) VALUES "
                    + "('i1','u1','t1','2026-09-10','2026-09-10','Asia/Shanghai','PENDING','晨间整理','LIFE',"
                    + "'NORMAL',TRUE,0,0)");
            assertThatThrownBy(() -> statement.execute("INSERT INTO task_instances "
                    + "(id,user_id,template_id,original_local_date,current_local_date,timezone,status,title,category,"
                    + "priority,all_day,postpone_count,version) VALUES "
                    + "('i2','u1','t1','2026-09-10','2026-09-11','UTC','PENDING','重复','LIFE','NORMAL',TRUE,0,0)"))
                    .isInstanceOf(java.sql.SQLException.class);
            assertThatThrownBy(() -> statement.execute("UPDATE task_templates SET category='BAD' WHERE id='t1'"))
                    .isInstanceOf(java.sql.SQLException.class);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM information_schema.indexes "
                    + "WHERE table_name IN ('task_templates','task_instances')")).isGreaterThanOrEqualTo(6);
        } finally {
            dataSource.destroy();
        }
    }

    @Test
    void upgradesV9ToV10AndCreatesNotificationTables() throws Exception {
        var dataSource = dataSource();
        try (var connection = dataSource.getConnection(); var statement = connection.createStatement()) {
            Flyway.configure().dataSource(dataSource).target(MigrationVersion.fromVersion("9")).load().migrate();
            statement.execute("INSERT INTO users (id,phone,status) VALUES ('u1','13000000903','ACTIVE')");
            statement.execute("INSERT INTO task_templates "
                    + "(id,user_id,source,title,category,priority,all_day,recurrence_type,effective_from,version,idempotency_key) "
                    + "VALUES ('t1','u1','USER','保留任务','WORK','IMPORTANT',TRUE,'NONE','2026-09-10',0,'keep')");
            Flyway.configure().dataSource(dataSource).load().migrate();
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM task_templates WHERE id='t1'")).isEqualTo(1);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM information_schema.tables WHERE table_name IN "
                    + "('task_settings','task_notification_events','task_operation_keys')")).isEqualTo(3);
            statement.execute("INSERT INTO task_settings (user_id) VALUES ('u1')");
            try (var result = statement.executeQuery("SELECT quiet_enabled,quiet_start_time,quiet_end_time "
                    + "FROM task_settings WHERE user_id='u1'")) {
                result.next();
                assertThat(result.getBoolean(1)).isTrue();
                assertThat(result.getTime(2).toLocalTime()).isEqualTo(java.time.LocalTime.of(22, 30));
                assertThat(result.getTime(3).toLocalTime()).isEqualTo(java.time.LocalTime.of(7, 0));
            }
            assertThatThrownBy(() -> statement.execute("INSERT INTO task_notification_events "
                    + "(id,user_id,device_key_hash,event_type,idempotency_key) "
                    + "VALUES ('e1','u1','hash','DELIVERED','bad')"))
                    .isInstanceOf(java.sql.SQLException.class);
        } finally {
            dataSource.destroy();
        }
    }

    @Test
    void upgradesV8DirectlyToV10() throws Exception {
        var dataSource = dataSource();
        try (var connection = dataSource.getConnection(); var statement = connection.createStatement()) {
            Flyway.configure().dataSource(dataSource).target(MigrationVersion.fromVersion("8")).load().migrate();
            statement.execute("INSERT INTO users (id,phone,status) VALUES ('direct','13000000904','ACTIVE')");
            Flyway.configure().dataSource(dataSource).load().migrate();
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM users WHERE id='direct'")).isEqualTo(1);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM information_schema.tables WHERE table_name IN "
                    + "('task_templates','task_instances','task_settings','task_notification_events')")).isEqualTo(4);
        } finally {
            dataSource.destroy();
        }
    }

    private SingleConnectionDataSource dataSource() {
        return new SingleConnectionDataSource("jdbc:h2:mem:task_migration_"
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
