package com.lightbite.healthy;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
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

@SpringBootTest
@ActiveProfiles("test")
class ProfileSectionsIntegrationTests {

    private static final String USER_A = "profile-sections-a";
    private static final String USER_B = "profile-sections-b";

    @Autowired WebApplicationContext applicationContext;
    @Autowired JdbcTemplate jdbc;
    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(applicationContext).apply(springSecurity()).build();
        createProfile(USER_A, "13800001001", "62.5", "花生");
        createProfile(USER_B, "13800001002", "78.0", "虾");
    }

    @Test
    void readsTheCompleteProfileAsStableCamelCaseSections() throws Exception {
        mockMvc.perform(get("/api/v1/profile/sections").with(user(USER_A)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.basicInfo.birthDate").value("1995-06-18"))
                .andExpect(jsonPath("$.basicInfo.metabolicBasis").value("FEMALE"))
                .andExpect(jsonPath("$.bodyData.heightCm").value(165))
                .andExpect(jsonPath("$.bodyData.latestMeasurement.weightKg").value(62.5))
                .andExpect(jsonPath("$.lifestyle.activityLevel").value("LIGHT"))
                .andExpect(jsonPath("$.dietaryPreferences.allergies").value("花生"))
                .andExpect(jsonPath("$.healthGoal.goalType").value("FAT_LOSS"))
                .andExpect(jsonPath("$.riskInfo.riskBlocked").value(false))
                .andExpect(jsonPath("$.complete").value(true))
                .andExpect(jsonPath("$.planNeedsRecalculation").value(false))
                .andExpect(jsonPath("$.basic_info").doesNotExist());

        mockMvc.perform(get("/api/v1/profile").with(user(USER_A)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.height_cm").value(165))
                .andExpect(jsonPath("$.bodyData").doesNotExist());
        mockMvc.perform(get("/api/v1/profile/sections").with(user(USER_B)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.bodyData.latestMeasurement.weightKg").value(78.0))
                .andExpect(jsonPath("$.dietaryPreferences.allergies").value("虾"));
    }

    @Test
    void savesAllSixSectionsIndependentlyAndMarksOnlyCriticalChanges() throws Exception {
        put("lifestyle", USER_A, """
                {"expectedVersion":4,"workStyle":"ACTIVE","sleepHours":8.0,"exerciseDays":4}
                """).andExpect(status().isOk())
                .andExpect(jsonPath("$.lifestyle.workStyle").value("ACTIVE"))
                .andExpect(jsonPath("$.planNeedsRecalculation").value(false));

        put("dietary-preferences", USER_A, """
                {"expectedVersion":5,"dietType":"HIGH_PROTEIN","allergies":"花生、牛奶","avoidFoods":"香菜"}
                """).andExpect(status().isOk())
                .andExpect(jsonPath("$.dietaryPreferences.dietType").value("HIGH_PROTEIN"))
                .andExpect(jsonPath("$.planNeedsRecalculation").value(false));

        put("body-data", USER_A, """
                {"expectedVersion":6,"weightKg":62.5,"waistCm":71,"bodyFatPercent":24.5}
                """).andExpect(status().isOk())
                .andExpect(jsonPath("$.bodyData.latestMeasurement.waistCm").value(71))
                .andExpect(jsonPath("$.planNeedsRecalculation").value(false));

        put("risk-info", USER_A, """
                {"expectedVersion":7,"pregnant":false,"breastfeeding":false,"eatingDisorderRisk":true,
                 "seriousChronicDisease":false,"unsafeTarget":false}
                """).andExpect(status().isOk())
                .andExpect(jsonPath("$.riskInfo.riskBlocked").value(true))
                .andExpect(jsonPath("$.planNeedsRecalculation").value(false));

        jdbc.update("UPDATE health_profiles SET risk_blocked=FALSE WHERE user_id=?", USER_A);
        put("basic-info", USER_A, "{\"expectedVersion\":8,\"birthDate\":\"1994-06-18\",\"sex\":\"FEMALE\"}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.planNeedsRecalculation").value(true));

        jdbc.update("UPDATE health_profiles SET plan_needs_recalculation=FALSE WHERE user_id=?", USER_A);
        put("body-data", USER_A, "{\"expectedVersion\":9,\"heightCm\":166}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.planNeedsRecalculation").value(true));

        jdbc.update("UPDATE health_profiles SET plan_needs_recalculation=FALSE WHERE user_id=?", USER_A);
        put("lifestyle", USER_A, "{\"expectedVersion\":10,\"activityLevel\":\"MODERATE\"}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.planNeedsRecalculation").value(true));

        jdbc.update("UPDATE health_profiles SET plan_needs_recalculation=FALSE WHERE user_id=?", USER_A);
        put("health-goal", USER_A, """
                {"expectedVersion":11,"goalType":"FAT_LOSS","targetWeightKg":54,"targetDate":"2027-04-01"}
                """).andExpect(status().isOk())
                .andExpect(jsonPath("$.healthGoal.targetWeightKg").value(54))
                .andExpect(jsonPath("$.planNeedsRecalculation").value(true));

        assertThat(jdbc.queryForObject("SELECT allergies FROM dietary_preferences WHERE user_id=?",
                String.class, USER_B)).isEqualTo("虾");
    }

    @Test
    void keepsExistingValidationAndAuthenticationBoundaries() throws Exception {
        mockMvc.perform(get("/api/v1/profile/sections")).andExpect(status().isUnauthorized());
        put("basic-info", USER_A, "{\"expectedVersion\":4,\"birthDate\":\"2030-01-01\"}")
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("出生日期不正确"));
        put("lifestyle", USER_A, "{\"expectedVersion\":4,\"activityLevel\":\"EXTREME\"}")
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("选项不受支持"));
    }

    @Test
    void rejectsStaleSectionWritesMissingRiskFieldsAndUnavailableGoals() throws Exception {
        put("basic-info", USER_A,
                "{\"expectedVersion\":4,\"birthDate\":\"1994-06-18\"}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.profileVersion").value(5));

        put("lifestyle", USER_A,
                "{\"expectedVersion\":4,\"workStyle\":\"ACTIVE\"}")
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("PROFILE_VERSION_CONFLICT"))
                .andExpect(jsonPath("$.message").value("健康档案已更新，请刷新后重试"));
        assertThat(jdbc.queryForObject("SELECT work_style FROM health_profiles WHERE user_id=?",
                String.class, USER_A)).isEqualTo("SEDENTARY");

        put("risk-info", USER_A, "{\"expectedVersion\":5,\"pregnant\":true}")
                .andExpect(status().isBadRequest());

        put("health-goal", USER_A,
                "{\"expectedVersion\":5,\"goalType\":\"MUSCLE_GAIN\"}")
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("PLAN_GOAL_UNSUPPORTED"));
        assertThat(jdbc.queryForObject("SELECT goal_type FROM health_goals WHERE user_id=?",
                String.class, USER_A)).isEqualTo("FAT_LOSS");
        assertThat(jdbc.queryForObject("SELECT version FROM health_profiles WHERE user_id=?",
                Integer.class, USER_A)).isEqualTo(5);
    }

    @Test
    void partialBodySaveCarriesForwardUnchangedMeasurementFields() throws Exception {
        put("body-data", USER_A, "{\"expectedVersion\":4,\"waistCm\":73}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.bodyData.latestMeasurement.weightKg").value(62.5))
                .andExpect(jsonPath("$.bodyData.latestMeasurement.waistCm").value(73))
                .andExpect(jsonPath("$.bodyData.latestMeasurement.bodyFatPercent").value(25))
                .andExpect(jsonPath("$.planNeedsRecalculation").value(false))
                .andExpect(jsonPath("$.profileVersion").value(5));
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM body_measurements WHERE user_id=?",
                Integer.class, USER_A)).isEqualTo(2);
    }

    private org.springframework.test.web.servlet.ResultActions put(String section, String userId, String body)
            throws Exception {
        return mockMvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders
                .put("/api/v1/profile/sections/{section}", section).with(user(userId))
                .contentType(MediaType.APPLICATION_JSON).content(body));
    }

    private void createProfile(String userId, String phone, String weight, String allergies) {
        jdbc.update("MERGE INTO users (id,phone,status) KEY(id) VALUES (?,?,'ACTIVE')", userId, phone);
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
        jdbc.update("INSERT INTO body_measurements (id,user_id,weight_kg,waist_cm,body_fat_percent) "
                + "VALUES (RANDOM_UUID(),?,?,72,25)", userId, new java.math.BigDecimal(weight));
        jdbc.update("INSERT INTO health_goals (user_id,goal_type,target_weight_kg,target_date) "
                + "VALUES (?,'FAT_LOSS',55,'2027-03-01')", userId);
        jdbc.update("INSERT INTO dietary_preferences (user_id,diet_type,allergies,avoid_foods) "
                + "VALUES (?,'BALANCED',?,'香菜')", userId, allergies);
        jdbc.update("INSERT INTO health_risk_answers (id,user_id,risk_blocked) VALUES (RANDOM_UUID(),?,FALSE)", userId);
    }
}
