package com.lightbite.healthy;

import static org.assertj.core.api.Assertions.assertThat;

import java.sql.DriverManager;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationVersion;
import org.junit.jupiter.api.Test;

class FatLossMigrationTests {

    @Test
    void v4BackfillsBinarySexButLeavesOtherForExplicitChoice() throws Exception {
        String url = "jdbc:h2:mem:migration_" + UUID.randomUUID()
                + ";MODE=MySQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1";
        Flyway.configure().dataSource(url, "sa", "")
                .target(MigrationVersion.fromVersion("3")).load().migrate();
        try (var connection = DriverManager.getConnection(url, "sa", "");
             var statement = connection.createStatement()) {
            statement.execute("INSERT INTO users (id,phone,status) VALUES ('female','13000000001','ACTIVE')");
            statement.execute("INSERT INTO users (id,phone,status) VALUES ('other','13000000002','ACTIVE')");
            statement.execute("INSERT INTO health_profiles (user_id,sex,current_step,completed) "
                    + "VALUES ('female','FEMALE',7,TRUE),('other','OTHER',7,TRUE)");
        }

        Flyway.configure().dataSource(url, "sa", "").load().migrate();

        try (var connection = DriverManager.getConnection(url, "sa", "");
             var statement = connection.createStatement()) {
            var result = statement.executeQuery(
                    "SELECT user_id,metabolic_basis FROM health_profiles ORDER BY user_id");
            assertThat(result.next()).isTrue();
            assertThat(result.getString("user_id")).isEqualTo("female");
            assertThat(result.getString("metabolic_basis")).isEqualTo("FEMALE");
            assertThat(result.next()).isTrue();
            assertThat(result.getString("user_id")).isEqualTo("other");
            assertThat(result.getString("metabolic_basis")).isNull();
        }
    }
}
