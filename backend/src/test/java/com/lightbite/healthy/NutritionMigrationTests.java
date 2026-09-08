package com.lightbite.healthy;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.sql.DriverManager;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationVersion;
import org.junit.jupiter.api.Test;

class NutritionMigrationTests {

    @Test
    void migratesAnEmptyDatabaseWithFoodsPortionsAndMealEntries() throws Exception {
        String url = databaseUrl();

        Flyway.configure().dataSource(url, "sa", "").load().migrate();

        try (var connection = DriverManager.getConnection(url, "sa", "");
             var statement = connection.createStatement()) {
            assertThat(tableCount(statement, "foods")).isEqualTo(1);
            assertThat(tableCount(statement, "food_portions")).isEqualTo(1);
            assertThat(tableCount(statement, "meal_entries")).isEqualTo(1);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM foods WHERE owner_user_id IS NULL"))
                    .isBetween(38, 45);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM food_portions")).isGreaterThanOrEqualTo(38);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM foods WHERE name='米饭'")) .isEqualTo(1);
            assertThatThrownBy(() -> statement.execute("INSERT INTO foods "
                    + "(id,name,category,calories_per_100g,protein_per_100g,carbs_per_100g,fat_per_100g) "
                    + "VALUES ('duplicate-rice','米饭','STAPLE',116,2.6,25.9,.3)"))
                    .isInstanceOf(java.sql.SQLException.class);
        }
    }

    @Test
    void upgradesV4WithoutChangingExistingAccountProfileOrPlan() throws Exception {
        String url = databaseUrl();
        Flyway.configure().dataSource(url, "sa", "")
                .target(MigrationVersion.fromVersion("4")).load().migrate();
        try (var connection = DriverManager.getConnection(url, "sa", "");
             var statement = connection.createStatement()) {
            statement.execute("INSERT INTO users (id,phone,status) VALUES ('u1','13000000001','ACTIVE')");
            statement.execute("INSERT INTO health_profiles (user_id,current_step,completed) VALUES ('u1',7,TRUE)");
            statement.execute("INSERT INTO health_plans (id,user_id,status,phase_start_date,phase_end_date,current_version) "
                    + "VALUES ('p1','u1','ACTIVE','2026-09-01','2026-09-28',1)");
        }

        Flyway.configure().dataSource(url, "sa", "").load().migrate();

        try (var connection = DriverManager.getConnection(url, "sa", "");
             var statement = connection.createStatement()) {
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM users WHERE id='u1' AND status='ACTIVE'"))
                    .isEqualTo(1);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM health_profiles WHERE user_id='u1' AND completed=TRUE"))
                    .isEqualTo(1);
            assertThat(queryInt(statement, "SELECT COUNT(*) FROM health_plans WHERE id='p1' AND status='ACTIVE'"))
                    .isEqualTo(1);
        }
    }

    private String databaseUrl() {
        return "jdbc:h2:mem:nutrition_migration_" + UUID.randomUUID()
                + ";MODE=MySQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1";
    }

    private int tableCount(java.sql.Statement statement, String table) throws Exception {
        return queryInt(statement, "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='" + table + "'");
    }

    private int queryInt(java.sql.Statement statement, String sql) throws Exception {
        try (var result = statement.executeQuery(sql)) {
            result.next();
            return result.getInt(1);
        }
    }
}
