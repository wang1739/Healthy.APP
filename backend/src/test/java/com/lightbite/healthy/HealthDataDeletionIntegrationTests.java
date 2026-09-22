package com.lightbite.healthy;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import java.time.LocalDate;
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
class HealthDataDeletionIntegrationTests {
    private static final String USER = "health-delete-user";
    private static final String PHONE = "13600004001";
    @Autowired WebApplicationContext context;
    @Autowired JdbcTemplate jdbc;
    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();
        jdbc.update("DELETE FROM health_report_sources WHERE report_id IN ('related-report','unrelated-report')");
        jdbc.update("DELETE FROM health_reports WHERE id IN ('related-report','unrelated-report')");
        jdbc.update("DELETE FROM hydration_entries WHERE id='delete-water'");
        jdbc.update("DELETE FROM health_plan_versions WHERE plan_id IN (SELECT id FROM health_plans WHERE user_id=?)", USER);
        jdbc.update("DELETE FROM health_plans WHERE user_id=?", USER);
        jdbc.update("DELETE FROM body_measurements WHERE user_id=?", USER);
        jdbc.update("DELETE FROM health_goals WHERE user_id=?", USER);
        jdbc.update("DELETE FROM dietary_preferences WHERE user_id=?", USER);
        jdbc.update("DELETE FROM health_risk_answers WHERE user_id=?", USER);
        jdbc.update("DELETE FROM health_profiles WHERE user_id=?", USER);
        jdbc.update("DELETE FROM verification_codes WHERE phone=? AND purpose='HEALTH_DATA_DELETE'", PHONE);
        jdbc.update("MERGE INTO users (id,phone,status) KEY(id) VALUES (?,?,'ACTIVE')", USER, PHONE);
        jdbc.update("INSERT INTO hydration_entries (id,user_id,amount_ml,occurred_at,timezone,source,idempotency_key) "
                + "VALUES ('delete-water',?,300,CURRENT_TIMESTAMP,'Asia/Shanghai','CUSTOM','delete-water')", USER);
        report("related-report", "related-key", 1);
        report("unrelated-report", "unrelated-key", 2);
        jdbc.update("INSERT INTO health_report_sources (report_id,section_code,metric_code,source_type,source_id,source_local_date,location_label) "
                + "VALUES ('related-report','HYDRATION','TOTAL','HYDRATION_ENTRY','delete-water',CURRENT_DATE,'饮水记录')");
    }

    @Test
    void previewIsServerCalculatedAndDeletingSourceRemovesOnlyRelatedReport() throws Exception {
        mockMvc.perform(post("/api/v1/health-data-deletion/preview").with(user(USER))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"dataTypes\":[\"HYDRATION\"]}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.recordCounts.HYDRATION").value(1))
                .andExpect(jsonPath("$.affectedReports").value(1));

        String codeBody = mockMvc.perform(post("/api/v1/auth/sms/send").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"phone\":\"%s\",\"purpose\":\"HEALTH_DATA_DELETE\"}".formatted(PHONE)))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        String code = JsonPath.read(codeBody, "$.debugCode");
        mockMvc.perform(post("/api/v1/health-data-deletion").with(user(USER))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"dataTypes\":[\"HYDRATION\"],\"code\":\"%s\"}".formatted(code)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("已完成"));

        assertThat(count("hydration_entries", "id='delete-water'")).isZero();
        assertThat(count("health_reports", "id='related-report'")).isZero();
        assertThat(count("health_reports", "id='unrelated-report'")).isEqualTo(1);
    }

    @Test
    void deletingTheLastActiveVersionAlsoRemovesAnUnconfirmedPreview() throws Exception {
        jdbc.update("""
                INSERT INTO health_profiles
                (user_id,birth_date,sex,metabolic_basis,height_cm,activity_level,work_style,sleep_hours,
                 exercise_days,current_step,completed,risk_blocked,plan_needs_recalculation,version)
                VALUES (?,'1995-06-18','FEMALE','FEMALE',165,'LIGHT','SEDENTARY',7.5,2,7,TRUE,FALSE,FALSE,1)
                """, USER);
        jdbc.update("INSERT INTO health_goals (user_id,goal_type,target_weight_kg,target_date) "
                + "VALUES (?,'FAT_LOSS',55,?)", USER, LocalDate.now().plusMonths(6));
        jdbc.update("""
                INSERT INTO body_measurements (id,user_id,weight_kg,measured_at)
                VALUES ('delete-weight-old',?,?,?)
                """, USER, new java.math.BigDecimal("62.5"),
                java.sql.Timestamp.valueOf(LocalDate.now().minusDays(1).atTime(12, 0)));
        mockMvc.perform(post("/api/v1/plans").with(user(USER))
                        .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isCreated());
        String planId = jdbc.queryForObject(
                "SELECT id FROM health_plans WHERE user_id=?", String.class, USER);

        jdbc.update("""
                INSERT INTO body_measurements (id,user_id,weight_kg,measured_at)
                VALUES ('delete-weight-new',?,?,?)
                """, USER, new java.math.BigDecimal("61.5"),
                java.sql.Timestamp.valueOf(LocalDate.now().atTime(12, 0)));
        jdbc.update("UPDATE health_profiles SET version=2,plan_needs_recalculation=TRUE WHERE user_id=?", USER);
        mockMvc.perform(post("/api/v1/plans/{id}/recalculate", planId).with(user(USER))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"expectedVersion\":1}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.state").value("PREVIEW"));
        assertThat(jdbc.queryForList("""
                SELECT version_number,status,source_measurement_id FROM health_plan_versions
                WHERE plan_id=? ORDER BY version_number
                """, planId)).extracting("VERSION_NUMBER", "STATUS", "SOURCE_MEASUREMENT_ID")
                .containsExactly(
                        org.assertj.core.groups.Tuple.tuple(1, "ACTIVE", "delete-weight-old"),
                        org.assertj.core.groups.Tuple.tuple(2, "PREVIEW", "delete-weight-new"));

        String codeBody = mockMvc.perform(post("/api/v1/auth/sms/send").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"phone\":\"%s\",\"purpose\":\"HEALTH_DATA_DELETE\"}".formatted(PHONE)))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        String code = JsonPath.read(codeBody, "$.debugCode");
        LocalDate oldDate = LocalDate.now().minusDays(1);
        mockMvc.perform(post("/api/v1/health-data-deletion").with(user(USER))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"dataTypes":["MEASUREMENTS"],"fromDate":"%s","toDate":"%s","code":"%s"}
                                """.formatted(oldDate, oldDate, code)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("已完成"));

        assertThat(count("health_plan_versions", "plan_id='" + planId + "'")).isZero();
        assertThat(count("health_plans", "id='" + planId + "'")).isZero();
        assertThat(count("body_measurements", "id='delete-weight-new'")).isEqualTo(1);
    }

    private void report(String id, String key, int version) {
        jdbc.update("INSERT INTO health_reports (id,user_id,report_type,period_start,period_end,timezone,period_status,"
                        + "version,rules_version,data_cutoff_at,input_hash,snapshot_json,idempotency_key) "
                        + "VALUES (?,?,'DAILY',?,?,'Asia/Shanghai','COMPLETE',?,'v1',CURRENT_TIMESTAMP,?,'{}',?)",
                id, USER, LocalDate.now(), LocalDate.now(), version, "0".repeat(64), key);
    }

    private int count(String table, String where) {
        return jdbc.queryForObject("SELECT COUNT(*) FROM " + table + " WHERE " + where, Integer.class);
    }
}
