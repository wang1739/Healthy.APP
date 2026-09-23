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
        jdbc.update("DELETE FROM health_report_sources WHERE report_id IN (SELECT id FROM health_reports WHERE user_id=?)", USER);
        jdbc.update("DELETE FROM health_reports WHERE user_id=?", USER);
        jdbc.update("DELETE FROM health_data_deletion_jobs WHERE user_id=?", USER);
        jdbc.update("DELETE FROM hydration_entries WHERE user_id=?", USER);
        jdbc.update("DELETE FROM task_notification_events WHERE user_id=?", USER);
        jdbc.update("DELETE FROM task_operation_keys WHERE user_id=?", USER);
        jdbc.update("DELETE FROM task_instances WHERE user_id=?", USER);
        jdbc.update("DELETE FROM task_templates WHERE user_id=?", USER);
        jdbc.update("DELETE FROM health_plan_versions WHERE plan_id IN (SELECT id FROM health_plans WHERE user_id=?)", USER);
        jdbc.update("DELETE FROM health_plans WHERE user_id=?", USER);
        jdbc.update("DELETE FROM body_measurements WHERE user_id=?", USER);
        jdbc.update("DELETE FROM health_goals WHERE user_id=?", USER);
        jdbc.update("DELETE FROM dietary_preferences WHERE user_id=?", USER);
        jdbc.update("DELETE FROM health_risk_answers WHERE user_id=?", USER);
        jdbc.update("DELETE FROM health_profiles WHERE user_id=?", USER);
        jdbc.update("DELETE FROM verification_codes WHERE phone=?", PHONE);
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
                        .contentType(MediaType.APPLICATION_JSON).content("{\"dataTypes\":[\"PROFILE\",\"REPORTS\"]}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.recordCounts.PROFILE").value(0))
                .andExpect(jsonPath("$.recordCounts.REPORTS").value(2));
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
    void dateRangeAndUserIsolationAreAppliedAndFailedVerificationRollsBack() throws Exception {
        jdbc.update("INSERT INTO hydration_entries (id,user_id,amount_ml,occurred_at,timezone,source,idempotency_key) "
                + "VALUES ('old-water',?,200,TIMESTAMP '2026-01-01 08:00:00','Asia/Shanghai','CUSTOM','old-water')", USER);
        jdbc.update("MERGE INTO users (id,phone,status) KEY(id) VALUES ('other-health-delete','13600004002','ACTIVE')");
        jdbc.update("MERGE INTO hydration_entries (id,user_id,amount_ml,occurred_at,timezone,source,idempotency_key) "
                + "KEY(id) VALUES ('other-water','other-health-delete',500,CURRENT_TIMESTAMP,'Asia/Shanghai','CUSTOM','other-water')");

        String range = LocalDate.now().toString();
        mockMvc.perform(post("/api/v1/health-data-deletion/preview").with(user(USER))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"dataTypes\":[\"HYDRATION\"],\"fromDate\":\"%s\",\"toDate\":\"%s\"}".formatted(range, range)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.recordCounts.HYDRATION").value(1));

        mockMvc.perform(post("/api/v1/health-data-deletion").with(user(USER))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"dataTypes\":[\"HYDRATION\"],\"fromDate\":\"%s\",\"toDate\":\"%s\",\"code\":\"000000\"}"
                                .formatted(range, range)))
                .andExpect(status().isUnauthorized());
        assertThat(count("hydration_entries", "id='delete-water'")).isEqualTo(1);
        assertThat(count("hydration_entries", "id='old-water'")).isEqualTo(1);
        assertThat(count("hydration_entries", "id='other-water'")).isEqualTo(1);
        assertThat(count("health_data_deletion_jobs", "user_id='" + USER + "'")).isZero();
    }

    @Test
    void taskDeletionUsesOriginalDateAndRemovesItsDependentReport() throws Exception {
        LocalDate originalDate = LocalDate.now();
        insertTask("delete-task", "USER", null, null, null, originalDate, originalDate.plusDays(1));
        jdbc.update("INSERT INTO task_notification_events "
                + "(id,user_id,task_instance_id,device_key_hash,event_type,idempotency_key) "
                + "VALUES ('delete-task-event',?,'delete-task','device','SCHEDULED','delete-task-event')", USER);
        jdbc.update("INSERT INTO task_operation_keys (user_id,idempotency_key,instance_id,operation_type) "
                + "VALUES (?,'delete-task-operation','delete-task','COMPLETE')", USER);
        report("task-report", "task-report-key", 3);
        reportSource("task-report", "TASKS", "completion", "TASK_INSTANCE", "delete-task", originalDate);

        String date = originalDate.toString();
        mockMvc.perform(post("/api/v1/health-data-deletion/preview").with(user(USER))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"dataTypes\":[\"TASKS\"],\"fromDate\":\"%s\",\"toDate\":\"%s\"}"
                                .formatted(date, date)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.recordCounts.TASKS").value(1))
                .andExpect(jsonPath("$.affectedReports").value(1));

        String code = verificationCode();
        mockMvc.perform(post("/api/v1/health-data-deletion").with(user(USER))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"dataTypes\":[\"TASKS\"],\"fromDate\":\"%s\",\"toDate\":\"%s\",\"code\":\"%s\"}"
                                .formatted(date, date, code)))
                .andExpect(status().isOk());

        assertThat(count("task_instances", "id='delete-task'")).isZero();
        assertThat(count("task_notification_events", "id='delete-task-event'")).isZero();
        assertThat(count("task_operation_keys", "idempotency_key='delete-task-operation'")).isZero();
        assertThat(count("task_templates", "id='delete-task-template'")).isEqualTo(1);
        assertThat(count("health_reports", "id='task-report'")).isZero();
    }

    @Test
    void deletingTheLastActiveVersionAlsoRemovesAnUnconfirmedPreview() throws Exception {
        String planId = createPlan("delete-weight-old", LocalDate.now().minusDays(1));

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
        String activeVersionId = jdbc.queryForObject(
                "SELECT id FROM health_plan_versions WHERE plan_id=? AND version_number=1", String.class, planId);
        report("plan-source-report", "plan-source-report-key", 3);
        reportSource("plan-source-report", "WEIGHT_PLAN", "plan", "PLAN_VERSION", activeVersionId,
                LocalDate.now().minusDays(1));

        LocalDate oldDate = LocalDate.now().minusDays(1);
        mockMvc.perform(post("/api/v1/health-data-deletion/preview").with(user(USER))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"dataTypes":["MEASUREMENTS"],"fromDate":"%s","toDate":"%s"}
                                """.formatted(oldDate, oldDate)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.affectedReports").value(1))
                .andExpect(jsonPath("$.affectedPlanVersions").value(2));
        mockMvc.perform(post("/api/v1/health-data-deletion").with(user(USER))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"dataTypes":["MEASUREMENTS"],"fromDate":"%s","toDate":"%s","code":"%s"}
                                """.formatted(oldDate, oldDate, verificationCode())))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("已完成"));

        assertThat(count("health_plan_versions", "plan_id='" + planId + "'")).isZero();
        assertThat(count("health_plans", "id='" + planId + "'")).isZero();
        assertThat(count("body_measurements", "id='delete-weight-new'")).isEqualTo(1);
        assertThat(count("health_reports", "id='plan-source-report'")).isZero();
    }

    @Test
    void profileDeletionRemovesDependentPlanAndPlanTasksButKeepsIndependentData() throws Exception {
        String planId = createPlan("profile-keep-measurement", LocalDate.now());
        String versionId = jdbc.queryForObject(
                "SELECT id FROM health_plan_versions WHERE plan_id=? AND version_number=1", String.class, planId);
        insertTask("profile-plan-task", "PLAN", planId, 1, "PROFILE_TEST", LocalDate.now(), LocalDate.now());
        insertTask("profile-user-task", "USER", null, null, null, LocalDate.now(), LocalDate.now());
        report("profile-plan-report", "profile-plan-report-key", 3);
        reportSource("profile-plan-report", "WEIGHT_PLAN", "plan", "PLAN_VERSION", versionId, LocalDate.now());
        report("profile-plan-task-report", "profile-plan-task-report-key", 4);
        reportSource("profile-plan-task-report", "TASKS", "completion", "TASK_INSTANCE",
                "profile-plan-task", LocalDate.now());
        report("profile-user-task-report", "profile-user-task-report-key", 5);
        reportSource("profile-user-task-report", "TASKS", "completion", "TASK_INSTANCE",
                "profile-user-task", LocalDate.now());

        mockMvc.perform(post("/api/v1/health-data-deletion/preview").with(user(USER))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"dataTypes\":[\"PROFILE\"]}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.recordCounts.PROFILE").value(1))
                .andExpect(jsonPath("$.affectedReports").value(2))
                .andExpect(jsonPath("$.affectedPlanVersions").value(1));
        mockMvc.perform(post("/api/v1/health-data-deletion").with(user(USER))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"dataTypes\":[\"PROFILE\"],\"code\":\"%s\"}".formatted(verificationCode())))
                .andExpect(status().isOk());

        assertThat(count("health_profiles", "user_id='" + USER + "'")).isZero();
        assertThat(count("health_plans", "id='" + planId + "'")).isZero();
        assertThat(count("task_instances", "id='profile-plan-task'")).isZero();
        assertThat(count("task_templates", "id='profile-plan-task-template'")).isZero();
        assertThat(count("health_reports", "id='profile-plan-report'")).isZero();
        assertThat(count("health_reports", "id='profile-plan-task-report'")).isZero();
        assertThat(count("body_measurements", "id='profile-keep-measurement'")).isEqualTo(1);
        assertThat(count("task_instances", "id='profile-user-task'")).isEqualTo(1);
        assertThat(count("task_templates", "id='profile-user-task-template'")).isEqualTo(1);
        assertThat(count("health_reports", "id='profile-user-task-report'")).isEqualTo(1);
    }

    private String createPlan(String measurementId, LocalDate measuredDate) throws Exception {
        jdbc.update("""
                INSERT INTO health_profiles
                (user_id,birth_date,sex,metabolic_basis,height_cm,activity_level,work_style,sleep_hours,
                 exercise_days,current_step,completed,risk_blocked,plan_needs_recalculation,version)
                VALUES (?,'1995-06-18','FEMALE','FEMALE',165,'LIGHT','SEDENTARY',7.5,2,7,TRUE,FALSE,FALSE,1)
                """, USER);
        jdbc.update("INSERT INTO health_goals (user_id,goal_type,target_weight_kg,target_date) "
                + "VALUES (?,'FAT_LOSS',55,?)", USER, LocalDate.now().plusMonths(6));
        jdbc.update("INSERT INTO body_measurements (id,user_id,weight_kg,measured_at) VALUES (?,?,62.5,?)",
                measurementId, USER, java.sql.Timestamp.valueOf(measuredDate.atTime(12, 0)));
        mockMvc.perform(post("/api/v1/plans").with(user(USER))
                        .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isCreated());
        return jdbc.queryForObject("SELECT id FROM health_plans WHERE user_id=?", String.class, USER);
    }

    private void insertTask(
            String id, String source, String planId, Integer planVersion, String taskCode,
            LocalDate originalDate, LocalDate currentDate
    ) {
        jdbc.update("""
                INSERT INTO task_templates
                (id,user_id,source,plan_id,plan_version,task_code,title,category,priority,all_day,
                 recurrence_type,effective_from,user_overridden)
                VALUES (?,?,?,?,?,?,'删除测试任务','HEALTH','NORMAL',TRUE,'NONE',?,FALSE)
                """, id + "-template", USER, source, planId, planVersion, taskCode, originalDate);
        jdbc.update("""
                INSERT INTO task_instances
                (id,user_id,template_id,original_local_date,current_local_date,timezone,status,title,
                 category,priority,all_day)
                VALUES (?,?,?, ?,?,'Asia/Shanghai','PENDING','删除测试任务','HEALTH','NORMAL',TRUE)
                """, id, USER, id + "-template", originalDate, currentDate);
    }

    private String verificationCode() throws Exception {
        String body = mockMvc.perform(post("/api/v1/auth/sms/send").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"phone\":\"%s\",\"purpose\":\"HEALTH_DATA_DELETE\"}".formatted(PHONE)))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.debugCode");
    }

    private void report(String id, String key, int version) {
        jdbc.update("INSERT INTO health_reports (id,user_id,report_type,period_start,period_end,timezone,period_status,"
                        + "version,rules_version,data_cutoff_at,input_hash,snapshot_json,idempotency_key) "
                        + "VALUES (?,?,'DAILY',?,?,'Asia/Shanghai','COMPLETE',?,'v1',CURRENT_TIMESTAMP,?,'{}',?)",
                id, USER, LocalDate.now(), LocalDate.now(), version, "0".repeat(64), key);
    }

    private void reportSource(
            String reportId, String section, String metric, String sourceType, String sourceId, LocalDate date
    ) {
        jdbc.update("""
                INSERT INTO health_report_sources
                (report_id,section_code,metric_code,source_type,source_id,source_local_date,location_label)
                VALUES (?,?,?,?,?,?,'删除测试来源')
                """, reportId, section, metric, sourceType, sourceId, date);
    }

    private int count(String table, String where) {
        return jdbc.queryForObject("SELECT COUNT(*) FROM " + table + " WHERE " + where, Integer.class);
    }
}
