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
