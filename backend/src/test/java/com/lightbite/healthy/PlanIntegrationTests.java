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
import com.jayway.jsonpath.JsonPath;
import java.time.LocalDate;

@SpringBootTest
@ActiveProfiles("test")
class PlanIntegrationTests {

    private static final String USER_A = "plan-user-a";
    private static final String USER_B = "plan-user-b";

    @Autowired WebApplicationContext applicationContext;
    @Autowired JdbcTemplate jdbc;
    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(applicationContext).apply(springSecurity()).build();
        jdbc.update("DELETE FROM health_plan_versions");
        jdbc.update("DELETE FROM health_plans");
        jdbc.update("DELETE FROM health_report_sources WHERE report_id IN ('measurement-report','unrelated-measurement-report')");
        jdbc.update("DELETE FROM health_reports WHERE id IN ('measurement-report','unrelated-measurement-report')");
        jdbc.update("DELETE FROM health_data_deletion_jobs WHERE user_id IN (?,?)", USER_A, USER_B);
        jdbc.update("DELETE FROM verification_codes WHERE phone IN ('13800000001','13800000002')");
        createCompleteProfile(USER_A, "13800000001");
        createCompleteProfile(USER_B, "13800000002");
    }

    @Test
    void previewDoesNotWriteAndConfirmationCreatesAuthoritativeVersion() throws Exception {
        mockMvc.perform(post("/api/v1/plans/preview").with(user(USER_A)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.ruleVersion").value("FAT_LOSS_V1"))
                .andExpect(jsonPath("$.targetKcal").isNumber())
                .andExpect(jsonPath("$.estimated").value(true));
        org.assertj.core.api.Assertions.assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM health_plans", Integer.class)).isZero();

        mockMvc.perform(post("/api/v1/plans").with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.state").value("ACTIVE"))
                .andExpect(jsonPath("$.currentVersion").value(1))
                .andExpect(jsonPath("$.currentWeek").value(1))
                .andExpect(jsonPath("$.plan.ruleVersion").value("FAT_LOSS_V1"));
        String measurementId = jdbc.queryForObject(
                "SELECT id FROM body_measurements WHERE user_id=? ORDER BY measured_at DESC,id DESC LIMIT 1",
                String.class, USER_A);
        org.assertj.core.api.Assertions.assertThat(jdbc.queryForObject(
                "SELECT source_measurement_id FROM health_plan_versions v JOIN health_plans p ON p.id=v.plan_id "
                        + "WHERE p.user_id=? AND v.version_number=1", String.class, USER_A))
                .isEqualTo(measurementId);

        mockMvc.perform(get("/api/v1/plans/current").with(user(USER_A)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.state").value("ACTIVE"))
                .andExpect(jsonPath("$.currentVersion").value(1));
        mockMvc.perform(get("/api/v1/plans/current").with(user(USER_B)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.state").value("EMPTY"));
    }

    @Test
    void generatedTenKcalTargetCanBeConfirmedAndPartialUpdatePreservesIt() throws Exception {
        mockMvc.perform(post("/api/v1/plans").with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"targetKcal\":1470,\"waterMl\":1900}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.plan.targetKcal").value(1470));
        String planId = jdbc.queryForObject(
                "SELECT id FROM health_plans WHERE user_id=?", String.class, USER_A);

        mockMvc.perform(put("/api/v1/plans/{id}/targets", planId).with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"expectedVersion\":1,\"waterMl\":2200}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.currentVersion").value(2))
                .andExpect(jsonPath("$.plan.targetKcal").value(1470))
                .andExpect(jsonPath("$.plan.waterMl").value(2200));
    }

    @Test
    void adjustmentRecalculationPauseResumeAndHistoryAreVersionedAndIsolated() throws Exception {
        String planId = createPlan(USER_A);

        mockMvc.perform(put("/api/v1/plans/{id}/targets", planId).with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"expectedVersion":1,"targetKcal":1520,"waterMl":2200,
                                 "exerciseDays":4,"exerciseMinutes":180,"sleepHours":8.0,
                                 "reason":"配合新的作息安排"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.currentVersion").value(2))
                .andExpect(jsonPath("$.plan.targetKcal").value(1520));

        mockMvc.perform(put("/api/v1/plans/{id}/targets", planId).with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{" + "\"expectedVersion\":1,\"waterMl\":2300}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("PLAN_VERSION_CONFLICT"));

        mockMvc.perform(put("/api/v1/profile").with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"heightCm\":166}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.planNeedsRecalculation").value(true));
        mockMvc.perform(get("/api/v1/plans/current").with(user(USER_A)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.state").value("NEEDS_RECALCULATION"));

        mockMvc.perform(post("/api/v1/plans/{id}/recalculate", planId).with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"expectedVersion\":2}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.currentVersion").value(3));

        mockMvc.perform(post("/api/v1/plans/{id}/pause", planId).with(user(USER_A)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.state").value("PAUSED"));
        mockMvc.perform(post("/api/v1/plans/{id}/resume", planId).with(user(USER_A)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.state").value("ACTIVE"));

        mockMvc.perform(get("/api/v1/plans/history?limit=10").with(user(USER_A)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(3))
                .andExpect(jsonPath("$[0].versionNumber").value(3));
        mockMvc.perform(post("/api/v1/plans/{id}/pause", planId).with(user(USER_B)))
                .andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("PLAN_NOT_FOUND"));
    }

    @Test
    void otherSexRequiresExplicitMetabolicBasisToCompleteProfile() throws Exception {
        jdbc.update("UPDATE health_profiles SET sex='OTHER', metabolic_basis=NULL, completed=FALSE WHERE user_id=?", USER_A);
        mockMvc.perform(put("/api/v1/profile").with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"completed\":true}"))
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("PROFILE_INCOMPLETE"));
        mockMvc.perform(put("/api/v1/profile").with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"metabolicBasis\":\"FEMALE\",\"completed\":true}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.complete").value(true));
    }

    @Test
    void laterRiskBlockHidesActivePlanValues() throws Exception {
        createPlan(USER_A);

        mockMvc.perform(post("/api/v1/profile/risk-assessment").with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"pregnant":false,"breastfeeding":false,"eatingDisorderRisk":true,
                                 "seriousChronicDisease":false,"unsafeTarget":false}
                                """))
                .andExpect(status().isOk()).andExpect(jsonPath("$.riskBlocked").value(true));
        mockMvc.perform(get("/api/v1/plans/current").with(user(USER_A)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.state").value("RISK_BLOCKED"))
                .andExpect(jsonPath("$.plan").doesNotExist());
    }

    @Test
    void deletingSourceMeasurementDeletesLinkedPlanAndReportButKeepsUnrelatedReport() throws Exception {
        createPlan(USER_A);
        String measurementId = jdbc.queryForObject("SELECT source_measurement_id FROM health_plan_versions v "
                + "JOIN health_plans p ON p.id=v.plan_id WHERE p.user_id=?", String.class, USER_A);
        report("measurement-report", "measurement-report-key", 1);
        report("unrelated-measurement-report", "unrelated-measurement-key", 2);
        jdbc.update("INSERT INTO health_report_sources (report_id,section_code,metric_code,source_type,source_id,source_local_date,location_label) "
                + "VALUES ('measurement-report','WEIGHT_PLAN','WEIGHT','WEIGHT_MEASUREMENT',?,CURRENT_DATE,'体重记录')", measurementId);
        String codeBody = mockMvc.perform(post("/api/v1/auth/sms/send").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"phone\":\"13800000001\",\"purpose\":\"HEALTH_DATA_DELETE\"}"))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        String code = JsonPath.read(codeBody, "$.debugCode");

        mockMvc.perform(post("/api/v1/health-data-deletion").with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"dataTypes\":[\"MEASUREMENTS\"],\"code\":\"%s\"}".formatted(code)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.deletedImpact.affectedPlanVersions").value(1));

        org.assertj.core.api.Assertions.assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM health_plans WHERE user_id=?", Integer.class, USER_A)).isZero();
        org.assertj.core.api.Assertions.assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM health_reports WHERE id='measurement-report'", Integer.class)).isZero();
        org.assertj.core.api.Assertions.assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM health_reports WHERE id='unrelated-measurement-report'", Integer.class)).isEqualTo(1);
    }

    private String createPlan(String userId) throws Exception {
        mockMvc.perform(post("/api/v1/plans").with(user(userId))
                        .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isCreated());
        return jdbc.queryForObject("SELECT id FROM health_plans WHERE user_id=?", String.class, userId);
    }

    private void report(String id, String key, int version) {
        jdbc.update("INSERT INTO health_reports (id,user_id,report_type,period_start,period_end,timezone,period_status,"
                        + "version,rules_version,data_cutoff_at,input_hash,snapshot_json,idempotency_key) "
                        + "VALUES (?,?,'DAILY',?,?,'Asia/Shanghai','COMPLETE',?,'v1',CURRENT_TIMESTAMP,?,'{}',?)",
                id, USER_A, LocalDate.now(), LocalDate.now(), version, "0".repeat(64), key);
    }

    private void createCompleteProfile(String userId, String phone) {
        jdbc.update("MERGE INTO users (id, phone, status) KEY(id) VALUES (?, ?, 'ACTIVE')", userId, phone);
        TestHealthAuthorization.grant(jdbc, userId);
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
        jdbc.update("INSERT INTO body_measurements (id,user_id,weight_kg) VALUES (RANDOM_UUID(),?,62.5)", userId);
        jdbc.update("INSERT INTO health_goals (user_id,goal_type,target_weight_kg,target_date) VALUES (?,'FAT_LOSS',55,'2027-03-01')", userId);
        jdbc.update("INSERT INTO dietary_preferences (user_id,diet_type) VALUES (?,'BALANCED')", userId);
        jdbc.update("INSERT INTO health_risk_answers (id,user_id,risk_blocked) VALUES (RANDOM_UUID(),?,FALSE)", userId);
    }
}
