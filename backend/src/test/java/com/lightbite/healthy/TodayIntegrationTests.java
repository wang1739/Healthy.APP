package com.lightbite.healthy;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
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
    }

    @Test
    void returnsEmptyPlanLatestWeightAndFutureModuleStates() throws Exception {
        mockMvc.perform(get("/api/v1/today?date=2026-09-08").with(user(USER_A)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.date").value("2026-09-08"))
                .andExpect(jsonPath("$.plan.status").value("EMPTY"))
                .andExpect(jsonPath("$.weight.status").value("READY"))
                .andExpect(jsonPath("$.weight.valueKg").value(62.5))
                .andExpect(jsonPath("$.nutrition.status").value("COMING_SOON"))
                .andExpect(jsonPath("$.nextAction.type").value("CREATE_PLAN"));

        mockMvc.perform(get("/api/v1/today?date=2026-09-08").with(user(USER_B)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.weight.valueKg").value(78.4));
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
