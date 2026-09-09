package com.lightbite.healthy;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;

@SpringBootTest
@ActiveProfiles("test")
class TodayIntegrationTests {

    private static final String USER_A = "today-user-a";
    private static final String USER_B = "today-user-b";
    @Autowired WebApplicationContext applicationContext;
    @Autowired JdbcTemplate jdbc;
    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(applicationContext).apply(springSecurity()).build();
        jdbc.update("DELETE FROM hydration_entries");
        jdbc.update("DELETE FROM hydration_settings");
        jdbc.update("DELETE FROM activity_records");
        jdbc.update("DELETE FROM sleep_record_tags");
        jdbc.update("DELETE FROM sleep_records");
        jdbc.update("DELETE FROM meal_entries");
        jdbc.update("DELETE FROM health_plan_versions");
        jdbc.update("DELETE FROM health_plans");
        createProfile(USER_A, "13800000011", "62.5");
        createProfile(USER_B, "13800000012", "78.4");
    }

    @Test
    void requiresAuthenticationAndValidDate() throws Exception {
        mockMvc.perform(get("/api/v1/today?date=2026-09-08"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/api/v1/today?date=08-09-2026").with(user(USER_A)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"))
                .andExpect(jsonPath("$.message").value("请求参数格式不正确"))
                .andExpect(jsonPath("$.fieldErrors[0].field").value("date"));

        mockMvc.perform(get("/api/v1/today").with(user(USER_A)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"))
                .andExpect(jsonPath("$.message").value("缺少必要的请求参数"))
                .andExpect(jsonPath("$.fieldErrors[0].field").value("date"));
    }

    @Test
    void returnsEmptyPlanLatestWeightAndEmptyNutrition() throws Exception {
        mockMvc.perform(get("/api/v1/today?date=2026-09-08").with(user(USER_A)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.date").value("2026-09-08"))
                .andExpect(jsonPath("$.plan.status").value("EMPTY"))
                .andExpect(jsonPath("$.weight.status").value("READY"))
                .andExpect(jsonPath("$.weight.valueKg").value(62.5))
                .andExpect(jsonPath("$.nutrition.status").value("EMPTY"))
                .andExpect(jsonPath("$.nutrition.consumedKcal").value(0))
                .andExpect(jsonPath("$.nutrition.targetKcal").doesNotExist())
                .andExpect(jsonPath("$.hydration.status").value("EMPTY"))
                .andExpect(jsonPath("$.hydration.consumedMl").value(0))
                .andExpect(jsonPath("$.hydration.targetMl").value(2000))
                .andExpect(jsonPath("$.nextAction.type").value("CREATE_PLAN"));

        mockMvc.perform(get("/api/v1/today?date=2026-09-08").with(user(USER_B)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.weight.valueKg").value(78.4));
    }

    @Test
    void returnsRealHydrationSummary() throws Exception {
        jdbc.update("""
                INSERT INTO hydration_entries
                (id,user_id,amount_ml,occurred_at,timezone,source,idempotency_key)
                VALUES ('today-water',?,750,'2026-09-08 08:00:00','Asia/Shanghai','QUICK','today-water-key')
                """, USER_A);

        mockMvc.perform(get("/api/v1/today?date=2026-09-08").with(user(USER_A)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.hydration.status").value("READY"))
                .andExpect(jsonPath("$.hydration.consumedMl").value(750))
                .andExpect(jsonPath("$.hydration.targetMl").value(2000))
                .andExpect(jsonPath("$.hydration.remainingMl").value(1250))
                .andExpect(jsonPath("$.hydration.progress").value(0.375));
    }

    @Test
    void returnsRealActivitySummary() throws Exception {
        jdbc.update("""
                INSERT INTO activity_records
                (id,user_id,activity_type_id,activity_name_snapshot,intensity,duration_minutes,occurred_at,
                 timezone,weight_kg_snapshot,met_snapshot,calculation_version,estimated_kcal,final_kcal,
                 calorie_source,source,idempotency_key)
                VALUES ('today-activity',?,'act-walking','步行','MEDIUM',30,'2026-09-08 08:00:00',
                        'Asia/Shanghai',62.5,3.5,'MET_V1',109,120,'USER_OVERRIDE','MANUAL','today-activity-key')
                """, USER_A);

        mockMvc.perform(get("/api/v1/today?date=2026-09-08&timezone=Asia/Shanghai").with(user(USER_A)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.activity.status").value("NO_PLAN"))
                .andExpect(jsonPath("$.activity.todayDurationMinutes").value(30))
                .andExpect(jsonPath("$.activity.todayKcal").value(120))
                .andExpect(jsonPath("$.activity.todayRecordCount").value(1))
                .andExpect(jsonPath("$.activity.weekExerciseDays").value(1))
                .andExpect(jsonPath("$.activity.weekDurationMinutes").value(30))
                .andExpect(jsonPath("$.activity.targetExerciseDays").doesNotExist());
    }

    @Test
    void returnsRealSleepSummary() throws Exception {
        jdbc.update("""
                INSERT INTO sleep_records
                (id,user_id,record_type,started_at,ended_at,timezone,wake_local_date,active_night_wake_date,duration_minutes,
                 quality_score,source,idempotency_key)
                VALUES ('today-sleep',?,'NIGHT','2026-09-07 22:00:00','2026-09-08 06:00:00','UTC',
                        '2026-09-08','2026-09-08',480,4,'MANUAL','today-sleep-key')
                """, USER_A);
        mockMvc.perform(get("/api/v1/today?date=2026-09-08&timezone=UTC").with(user(USER_A)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.sleep.status").value("NO_PLAN"))
                .andExpect(jsonPath("$.sleep.nightDurationMinutes").value(480))
                .andExpect(jsonPath("$.sleep.qualityScore").value(4))
                .andExpect(jsonPath("$.sleep.qualityLabel").value("良好"))
                .andExpect(jsonPath("$.sleep.napDurationMinutes").value(0))
                .andExpect(jsonPath("$.sleep.hasEnoughTrendData").value(false));
    }

    @Test
    void usesClientTimezoneForHydrationAndKeepsOmittedTimezoneCompatible() throws Exception {
        Instant occurredAt = Instant.parse("2026-09-08T12:30:00Z");
        ZoneId serverZone = ZoneId.systemDefault();
        ZoneId clientZone = ZoneId.of("Pacific/Kiritimati");
        LocalDate serverDate = occurredAt.atZone(serverZone).toLocalDate();
        if (occurredAt.atZone(clientZone).toLocalDate().equals(serverDate)) {
            clientZone = ZoneId.of("Pacific/Pago_Pago");
        }
        LocalDate clientDate = occurredAt.atZone(clientZone).toLocalDate();

        jdbc.update("""
                INSERT INTO hydration_entries
                (id,user_id,amount_ml,occurred_at,timezone,source,idempotency_key)
                VALUES ('timezone-water',?,300,?,'Asia/Shanghai','QUICK','timezone-key')
                """, USER_A, Timestamp.from(occurredAt));

        mockMvc.perform(get("/api/v1/today").param("date", clientDate.toString())
                        .param("timezone", clientZone.getId()).with(user(USER_A)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.hydration.status").value("READY"))
                .andExpect(jsonPath("$.hydration.consumedMl").value(300));

        mockMvc.perform(get("/api/v1/today").param("date", serverDate.toString()).with(user(USER_A)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.hydration.consumedMl").value(300));
    }

    @Test
    void returnsRealNutritionTotalsAndActiveTarget() throws Exception {
        mockMvc.perform(post("/api/v1/plans").with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isCreated());
        jdbc.update("INSERT INTO meal_entries (id,user_id,entry_date,meal_type,food_id,food_name_snapshot,grams,"
                + "calories_snapshot,protein_snapshot,carbs_snapshot,fat_snapshot,idempotency_key) "
                + "VALUES ('today-meal',?,'2026-09-08','LUNCH','sys-rice','米饭',150,174,3.9,38.85,.45,'today-key')",
                USER_A);

        mockMvc.perform(get("/api/v1/today?date=2026-09-08").with(user(USER_A)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nutrition.status").value("READY"))
                .andExpect(jsonPath("$.nutrition.consumedKcal").value(174))
                .andExpect(jsonPath("$.nutrition.proteinG").value(3.9))
                .andExpect(jsonPath("$.nutrition.targetKcal").isNumber());
    }

    @Test
    void returnsConfirmedPlanTargets() throws Exception {
        mockMvc.perform(post("/api/v1/plans").with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isCreated());

        mockMvc.perform(get("/api/v1/today?date=2026-09-08").with(user(USER_A)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.plan.status").value("READY"))
                .andExpect(jsonPath("$.plan.state").value("ACTIVE"))
                .andExpect(jsonPath("$.plan.targetKcal").isNumber())
                .andExpect(jsonPath("$.plan.proteinG").isNumber())
                .andExpect(jsonPath("$.nextAction.type").value("VIEW_PLAN"));
    }

    @Test
    void returnsNewestWeightAndSafePlanLifecycleStates() throws Exception {
        jdbc.update("UPDATE body_measurements SET measured_at=? WHERE user_id=?",
                java.sql.Timestamp.from(java.time.Instant.parse("2026-09-06T08:00:00Z")), USER_A);
        jdbc.update("INSERT INTO body_measurements (id,user_id,weight_kg,measured_at) VALUES (RANDOM_UUID(),?,?,?)",
                USER_A, new java.math.BigDecimal("61.8"),
                java.sql.Timestamp.from(java.time.Instant.parse("2026-09-07T08:00:00Z")));
        mockMvc.perform(post("/api/v1/plans").with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isCreated());
        String planId = jdbc.queryForObject(
                "SELECT id FROM health_plans WHERE user_id=?", String.class, USER_A);

        mockMvc.perform(put("/api/v1/profile").with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"heightCm\":166}"))
                .andExpect(status().isOk());
        mockMvc.perform(get("/api/v1/today?date=2026-09-08").with(user(USER_A)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.weight.valueKg").value(61.8))
                .andExpect(jsonPath("$.plan.state").value("NEEDS_RECALCULATION"))
                .andExpect(jsonPath("$.plan.targetKcal").isNumber());

        mockMvc.perform(post("/api/v1/plans/{id}/pause", planId).with(user(USER_A)))
                .andExpect(status().isOk());
        mockMvc.perform(get("/api/v1/today?date=2026-09-08").with(user(USER_A)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.plan.state").value("PAUSED"))
                .andExpect(jsonPath("$.nextAction.type").value("RESUME_PLAN"));

        mockMvc.perform(post("/api/v1/profile/risk-assessment").with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"pregnant":false,"breastfeeding":false,"eatingDisorderRisk":true,
                                 "seriousChronicDisease":false,"unsafeTarget":false}
                                """))
                .andExpect(status().isOk());
        mockMvc.perform(get("/api/v1/today?date=2026-09-08").with(user(USER_A)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.plan.state").value("RISK_BLOCKED"))
                .andExpect(jsonPath("$.plan.targetKcal").doesNotExist())
                .andExpect(jsonPath("$.nextAction.type").value("VIEW_RISK_GUIDANCE"));
    }

    @Test
    void hidesHistoricalPlanWhenProfileIsNoLongerComplete() throws Exception {
        mockMvc.perform(post("/api/v1/plans").with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isCreated());
        jdbc.update("UPDATE health_profiles SET completed=FALSE,current_step=2 WHERE user_id=?", USER_A);

        mockMvc.perform(get("/api/v1/today?date=2026-09-08").with(user(USER_A)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.plan.status").value("EMPTY"))
                .andExpect(jsonPath("$.plan.state").value("PROFILE_INCOMPLETE"))
                .andExpect(jsonPath("$.plan.targetKcal").doesNotExist())
                .andExpect(jsonPath("$.hydration.status").value("PROFILE_INCOMPLETE"))
                .andExpect(jsonPath("$.hydration.consumedMl").doesNotExist())
                .andExpect(jsonPath("$.activity.status").value("PROFILE_INCOMPLETE"))
                .andExpect(jsonPath("$.sleep.status").value("PROFILE_INCOMPLETE"))
                .andExpect(jsonPath("$.sleep.targetMinutes").doesNotExist())
                .andExpect(jsonPath("$.nextAction.type").value("COMPLETE_PROFILE"));
    }

    private void createProfile(String userId, String phone, String weight) {
        jdbc.update("MERGE INTO users (id, phone, status) KEY(id) VALUES (?, ?, 'ACTIVE')", userId, phone);
        jdbc.update("DELETE FROM health_risk_answers WHERE user_id=?", userId);
        jdbc.update("DELETE FROM body_measurements WHERE user_id=?", userId);
        jdbc.update("DELETE FROM health_goals WHERE user_id=?", userId);
        jdbc.update("DELETE FROM dietary_preferences WHERE user_id=?", userId);
        jdbc.update("DELETE FROM health_profiles WHERE user_id=?", userId);
        jdbc.update("""
                INSERT INTO health_profiles
                (user_id,birth_date,sex,metabolic_basis,height_cm,activity_level,work_style,sleep_hours,
                 exercise_days,current_step,completed,risk_blocked,plan_needs_recalculation,version)
                VALUES (?,'1995-06-18','FEMALE','FEMALE',165,'LIGHT','SEDENTARY',7.5,2,7,TRUE,FALSE,FALSE,4)
                """, userId);
        jdbc.update("INSERT INTO body_measurements (id,user_id,weight_kg) VALUES (RANDOM_UUID(),?,?)",
                userId, new java.math.BigDecimal(weight));
        jdbc.update("INSERT INTO health_goals (user_id,goal_type,target_weight_kg,target_date) VALUES (?,'FAT_LOSS',55,'2027-03-01')", userId);
        jdbc.update("INSERT INTO dietary_preferences (user_id,diet_type) VALUES (?,'BALANCED')", userId);
        jdbc.update("INSERT INTO health_risk_answers (id,user_id,risk_blocked) VALUES (RANDOM_UUID(),?,FALSE)", userId);
    }
}
