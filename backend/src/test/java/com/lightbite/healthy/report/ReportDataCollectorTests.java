package com.lightbite.healthy.report;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;

@SpringBootTest
@ActiveProfiles("test")
class ReportDataCollectorTests {
    private static final String USER_A = "collector-a";
    private static final String USER_B = "collector-b";

    @Autowired JdbcTemplate jdbc;
    @Autowired ReportDataCollector collector;
    @Autowired ReportPeriodPolicy periods;

    @BeforeEach
    void setUp() {
        jdbc.update("DELETE FROM health_plan_versions");
        jdbc.update("DELETE FROM health_plans");
        jdbc.update("DELETE FROM meal_entries WHERE user_id IN (?,?)", USER_A, USER_B);
        for (String id : List.of(USER_A, USER_B)) {
            jdbc.update("MERGE INTO users (id,phone,status) KEY(id) VALUES (?,?,'ACTIVE')", id,
                    USER_A.equals(id) ? "13000000991" : "13000000992");
            jdbc.update("MERGE INTO health_profiles (user_id,current_step,completed) KEY(user_id) VALUES (?,7,TRUE)", id);
        }
    }

    @Test
    void historicalPeriodDoesNotApplyPlanCreatedAfterThatPeriod() {
        plan(USER_A, "plan-a", "plan-version-a", Instant.parse("2026-09-01T00:00:00Z"), 1888);
        ReportDtos.Period january = periods.resolve("MONTHLY", LocalDate.of(2026, 1, 10), "Asia/Shanghai",
                Instant.parse("2026-09-10T06:00:00Z"));

        ReportDtos.Facts facts = collector.collect(USER_A, january);

        assertThat(facts.planVersion()).isNull();
        assertThat(facts.targets()).isEmpty();
        assertThat(facts.sources()).noneMatch(source -> source.sourceType().equals("PLAN_VERSION"));
    }

    @Test
    void sourceFactsAndReferencesNeverIncludeAnotherUsersRows() {
        meal(USER_A, "collector-meal-a", 1200);
        meal(USER_B, "collector-meal-b", 9000);
        ReportDtos.Period day = periods.resolve("DAILY", LocalDate.of(2026, 9, 10), "Asia/Shanghai",
                Instant.parse("2026-09-10T14:00:00Z"));

        ReportDtos.Facts facts = collector.collect(USER_A, day);

        @SuppressWarnings("unchecked")
        var nutrition = (java.util.Map<String, Object>) facts.metrics().get("nutrition");
        assertThat(nutrition.get("averageCalories").toString()).isEqualTo("1200.0");
        assertThat(facts.sources()).extracting(ReportDtos.Source::sourceId)
                .contains("collector-meal-a").doesNotContain("collector-meal-b");
    }

    private void plan(String userId, String planId, String versionId, Instant createdAt, int calories) {
        jdbc.update("""
                INSERT INTO health_plans(id,user_id,status,phase_start_date,phase_end_date,current_version,created_at,updated_at)
                VALUES(?,?,'ACTIVE','2026-01-01','2026-12-31',1,?,?)
                """, planId, userId, createdAt, createdAt);
        jdbc.update("""
                INSERT INTO health_plan_versions(id,plan_id,version_number,rule_version,profile_version,calculation_date,
                  age,metabolic_basis,height_cm,weight_kg,activity_level,target_weight_kg,requested_target_date,bmi,
                  bmr_kcal,tdee_kcal,target_kcal,protein_g,carbs_g,fat_g,water_ml,exercise_days,exercise_minutes,
                  sleep_hours,expected_weekly_change_kg,suggested_target_date,safety_message,created_at)
                VALUES(?,?,1,'FAT_LOSS_V1',1,'2026-09-01',30,'MALE',175,75,'MODERATE',70,'2026-12-31',24.5,
                  1700,2300,?,100,200,60,2000,3,120,8,0.5,'2026-12-31','测试',?)
                """, versionId, planId, calories, createdAt);
    }

    private void meal(String userId, String id, int calories) {
        jdbc.update("""
                INSERT INTO meal_entries(id,user_id,entry_date,meal_type,food_name_snapshot,grams,calories_snapshot,
                  protein_snapshot,carbs_snapshot,fat_snapshot,idempotency_key,updated_at)
                VALUES(?,?,'2026-09-10','DINNER','测试餐',100,?,20,30,10,?, '2026-09-10 12:00:00')
                """, id, userId, calories, id);
    }
}
