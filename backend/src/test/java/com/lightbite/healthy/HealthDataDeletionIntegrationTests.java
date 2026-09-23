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
        jdbc.execute("DROP TABLE IF EXISTS qa_hydration_guard");
        jdbc.update("DELETE FROM health_report_sources WHERE report_id IN (SELECT id FROM health_reports WHERE user_id=?)", USER);
        jdbc.update("DELETE FROM health_reports WHERE user_id=?", USER);
        jdbc.update("DELETE FROM health_data_deletion_jobs WHERE user_id=?", USER);
        jdbc.update("DELETE FROM hydration_entries WHERE user_id=?", USER);
        jdbc.update("DELETE FROM verification_codes WHERE phone=?", PHONE);
        jdbc.update("DELETE FROM users WHERE id=?", USER);
        jdbc.update("INSERT INTO users (id,phone,status) VALUES (?,?, 'ACTIVE')", USER, PHONE);
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
    void closedDateRangeIncludesBothBoundaries() throws Exception {
        jdbc.update("INSERT INTO hydration_entries (id,user_id,amount_ml,occurred_at,timezone,source,idempotency_key) VALUES "
                        + "('range-start',?,200,TIMESTAMP '2026-01-01 00:00:00','Asia/Shanghai','CUSTOM','range-start'),"
                        + "('range-end',?,200,TIMESTAMP '2026-01-02 23:59:59','Asia/Shanghai','CUSTOM','range-end'),"
                        + "('range-outside',?,200,TIMESTAMP '2026-01-03 00:00:00','Asia/Shanghai','CUSTOM','range-outside')",
                USER, USER, USER);
        String codeBody = mockMvc.perform(post("/api/v1/auth/sms/send").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"phone\":\"%s\",\"purpose\":\"HEALTH_DATA_DELETE\"}".formatted(PHONE)))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        String code = JsonPath.read(codeBody, "$.debugCode");

        mockMvc.perform(post("/api/v1/health-data-deletion").with(user(USER))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"dataTypes\":[\"HYDRATION\"],\"fromDate\":\"2026-01-01\","
                                + "\"toDate\":\"2026-01-02\",\"code\":\"%s\"}".formatted(code)))
                .andExpect(status().isOk());

        assertThat(count("hydration_entries", "id IN ('range-start','range-end')")).isZero();
        assertThat(count("hydration_entries", "id='range-outside'")).isEqualTo(1);
    }

    @Test
    void databaseFailureRollsBackSourceReportAndJobTogether() throws Exception {
        jdbc.execute("CREATE TABLE qa_hydration_guard (entry_id VARCHAR(36) PRIMARY KEY, "
                + "CONSTRAINT fk_qa_hydration_guard FOREIGN KEY (entry_id) REFERENCES hydration_entries(id))");
        jdbc.update("INSERT INTO qa_hydration_guard (entry_id) VALUES ('delete-water')");
        try {
            String codeBody = mockMvc.perform(post("/api/v1/auth/sms/send").contentType(MediaType.APPLICATION_JSON)
                            .content("{\"phone\":\"%s\",\"purpose\":\"HEALTH_DATA_DELETE\"}".formatted(PHONE)))
                    .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
            String code = JsonPath.read(codeBody, "$.debugCode");

            mockMvc.perform(post("/api/v1/health-data-deletion").with(user(USER))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"dataTypes\":[\"HYDRATION\"],\"code\":\"%s\"}".formatted(code)))
                    .andExpect(status().is5xxServerError());

            assertThat(count("hydration_entries", "id='delete-water'")).isEqualTo(1);
            assertThat(count("health_reports", "id='related-report'")).isEqualTo(1);
            assertThat(count("health_report_sources", "report_id='related-report'")).isEqualTo(1);
            assertThat(count("health_data_deletion_jobs", "user_id='" + USER + "'")).isZero();
        } finally {
            jdbc.execute("DROP TABLE qa_hydration_guard");
        }
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
