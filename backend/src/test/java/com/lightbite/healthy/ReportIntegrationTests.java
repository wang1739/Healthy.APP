package com.lightbite.healthy;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.asyncDispatch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.request;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;
import java.time.LocalDate;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import com.lightbite.healthy.report.ReportDtos;
import com.lightbite.healthy.report.ReportService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

@SpringBootTest
@ActiveProfiles("test")
class ReportIntegrationTests {
    private static final String USER_A = "report-api-a";
    private static final String USER_B = "report-api-b";
    @Autowired WebApplicationContext context;
    @Autowired JdbcTemplate jdbc;
    @Autowired ReportService reports;
    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();
        jdbc.update("DELETE FROM health_report_sources");
        jdbc.update("DELETE FROM health_reports");
        jdbc.update("DELETE FROM meal_entries WHERE user_id IN (?,?)", USER_A, USER_B);
        for (String id : List.of(USER_A, USER_B))
        {
            jdbc.update("MERGE INTO users (id,phone,display_name,status) KEY(id) VALUES (?,?,?,'ACTIVE')", id,
                    USER_A.equals(id) ? "13000000961" : "13000000962", USER_A.equals(id) ? "小李" : "他人");
            jdbc.update("MERGE INTO health_profiles (user_id,current_step,completed) KEY(user_id) VALUES (?,7,TRUE)", id);
        }
    }

    @Test
    void requiresAuthenticationAndValidatesChineseFields() throws Exception {
        mockMvc.perform(get("/api/v1/reports")).andExpect(status().isUnauthorized());
        mockMvc.perform(post("/api/v1/reports").with(user(USER_A)).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"type\":\"YEARLY\",\"date\":\"2026-09-10\",\"timezone\":\"坏时区\"}"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.message").value("生成报告需要 Idempotency-Key"));
    }

    @Test
    void coversGenerationVersionsIdempotencySourcesPdfDeletionAndIsolation() throws Exception {
        meal("meal-report-1", "2026-09-10", 1800);
        String body = "{\"type\":\"DAILY\",\"date\":\"2026-09-10\",\"timezone\":\"Asia/Shanghai\"}";
        MvcResult generated = mockMvc.perform(post("/api/v1/reports").with(user(USER_A)).header("Idempotency-Key", "report-1")
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk()).andExpect(jsonPath("$.created").value(true))
                .andExpect(jsonPath("$.version").value(1)).andExpect(jsonPath("$.snapshot.rulesVersion").value("REPORT_RULES_V1"))
                .andReturn();
        String id = generated.getResponse().getContentAsString().replaceAll(".*\"id\":\"([^\"]+)\".*", "$1");

        mockMvc.perform(post("/api/v1/reports").with(user(USER_A)).header("Idempotency-Key", "report-1")
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk()).andExpect(jsonPath("$.id").value(id)).andExpect(jsonPath("$.created").value(false));
        mockMvc.perform(post("/api/v1/reports").with(user(USER_A)).header("Idempotency-Key", "report-1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"type\":\"MONTHLY\",\"date\":\"2026-09-10\",\"timezone\":\"Asia/Shanghai\"}"))
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("IDEMPOTENCY_KEY_CONFLICT"));
        mockMvc.perform(get("/api/v1/reports").with(user(USER_A))).andExpect(status().isOk()).andExpect(jsonPath("$[0].id").value(id));
        mockMvc.perform(get("/api/v1/reports/{id}", id).with(user(USER_B))).andExpect(status().isNotFound());
        mockMvc.perform(get("/api/v1/reports/{id}/sources", id).with(user(USER_A)).param("section", "NUTRITION"))
                .andExpect(status().isOk()).andExpect(jsonPath("$[0].locationLabel").value("2026-09-10 饮食记录"));

        MvcResult pending = mockMvc.perform(get("/api/v1/reports/{id}/pdf", id).with(user(USER_A)))
                .andExpect(request().asyncStarted()).andReturn();
        mockMvc.perform(asyncDispatch(pending)).andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.APPLICATION_PDF))
                .andExpect(header().string("Content-Disposition", org.hamcrest.Matchers.containsString("filename*=UTF-8''")))
                .andExpect(result -> assertThat(result.getResponse().getContentAsByteArray()).startsWith("%PDF".getBytes()));

        meal("meal-report-2", "2026-09-10", 100);
        mockMvc.perform(post("/api/v1/reports").with(user(USER_A)).header("Idempotency-Key", "report-2")
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk()).andExpect(jsonPath("$.created").value(true)).andExpect(jsonPath("$.version").value(2));
        mockMvc.perform(delete("/api/v1/reports/{id}", id).with(user(USER_A))).andExpect(status().isOk()).andExpect(jsonPath("$.deleted").value(true));
        mockMvc.perform(get("/api/v1/reports/{id}", id).with(user(USER_A))).andExpect(status().isNotFound());
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM meal_entries WHERE user_id=?", Integer.class, USER_A)).isEqualTo(2);
    }

    @Test
    void concurrentGenerationCreatesOneVersion() throws Exception {
        var start = new CountDownLatch(1);
        var executor = Executors.newFixedThreadPool(4);
        try {
            java.util.ArrayList<Future<ReportDtos.ReportResponse>> calls = new java.util.ArrayList<>();
            for (int i = 0; i < 4; i++) {
                int index = i;
                calls.add(executor.submit(() -> { start.await(); return reports.generate(USER_A, "parallel-" + index,
                        new ReportDtos.GenerateRequest("DAILY", LocalDate.of(2026, 9, 10), "Asia/Shanghai")); }));
            }
            start.countDown();
            java.util.Set<String> ids = new java.util.HashSet<>();
            for (Future<ReportDtos.ReportResponse> call : calls) ids.add(call.get().id());
            assertThat(ids).hasSize(1);
            assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM health_reports WHERE user_id=?", Integer.class, USER_A)).isEqualTo(1);
        } finally { executor.shutdownNow(); }
    }

    private void meal(String id, String date, int calories) {
        jdbc.update("""
                INSERT INTO meal_entries(id,user_id,entry_date,meal_type,food_name_snapshot,grams,calories_snapshot,
                  protein_snapshot,carbs_snapshot,fat_snapshot,idempotency_key)
                VALUES(?, ?, ?, 'DINNER', '测试餐', 100, ?, 20, 30, 10, ?)
                """, id, USER_A, date, calories, id);
    }
}
