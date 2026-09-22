package com.lightbite.healthy;

import static org.assertj.core.api.Assertions.assertThat;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationVersion;
import org.junit.jupiter.api.Test;

class ProfilePlanMigrationTests {

    @Test
    void migratesEmptyDatabaseWithPlanVersionLifecycleStatus() throws Exception {
        String url = url();
        Flyway.configure().dataSource(url, "sa", "").load().migrate();
        try (Connection connection = DriverManager.getConnection(url, "sa", "");
             ResultSet columns = connection.getMetaData().getColumns(null, null,
                     "HEALTH_PLAN_VERSIONS", "STATUS")) {
            assertThat(columns.next()).isTrue();
        }
    }

    @Test
    void upgradesV12ByMarkingCurrentVersionActiveAndOlderVersionsHistory() throws Exception {
        String url = url();
        Flyway.configure().dataSource(url, "sa", "")
                .target(MigrationVersion.fromVersion("12")).load().migrate();
        try (Connection connection = DriverManager.getConnection(url, "sa", "");
             Statement statement = connection.createStatement()) {
            statement.execute("INSERT INTO users (id,phone,status) VALUES ('u1','13800001111','ACTIVE')");
            statement.execute("INSERT INTO health_plans (id,user_id,status,phase_start_date,phase_end_date,current_version) "
                    + "VALUES ('p1','u1','ACTIVE',CURRENT_DATE,CURRENT_DATE,2)");
            insertVersion(statement, 1);
            insertVersion(statement, 2);
        }
        Flyway.configure().dataSource(url, "sa", "").load().migrate();
        try (Connection connection = DriverManager.getConnection(url, "sa", "");
             Statement statement = connection.createStatement();
             ResultSet rows = statement.executeQuery(
                     "SELECT version_number,status FROM health_plan_versions ORDER BY version_number")) {
            assertThat(rows.next()).isTrue();
            assertThat(rows.getInt(1)).isEqualTo(1);
            assertThat(rows.getString(2)).isEqualTo("HISTORY");
            assertThat(rows.next()).isTrue();
            assertThat(rows.getInt(1)).isEqualTo(2);
            assertThat(rows.getString(2)).isEqualTo("ACTIVE");
        }
    }

    private void insertVersion(Statement statement, int version) throws Exception {
        statement.execute("""
                INSERT INTO health_plan_versions
                (id,plan_id,version_number,rule_version,profile_version,calculation_date,age,metabolic_basis,
                 height_cm,weight_kg,activity_level,target_weight_kg,requested_target_date,bmi,bmr_kcal,
                 tdee_kcal,target_kcal,protein_g,carbs_g,fat_g,water_ml,exercise_days,exercise_minutes,
                 sleep_hours,expected_weekly_change_kg,suggested_target_date,safety_message)
                VALUES ('v%s','p1',%s,'FAT_LOSS_V1',1,CURRENT_DATE,30,'FEMALE',165,62,'LIGHT',55,
                        CURRENT_DATE,22.8,1300,1800,1500,90,170,50,2000,3,150,8,0.5,CURRENT_DATE,'安全')
                """.formatted(version, version));
    }

    private String url() {
        return "jdbc:h2:mem:profile_plan_migration_" + UUID.randomUUID().toString().replace("-", "")
                + ";MODE=MySQL;DB_CLOSE_DELAY=-1";
    }
}
