package com.lightbite.healthy;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.lightbite.healthy.sleep.SleepDtos;
import com.lightbite.healthy.sleep.SleepService;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
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
class SleepIntegrationTests {
    private static final String USER_A = "sleep-api-a";
    private static final String USER_B = "sleep-api-b";
    @Autowired WebApplicationContext applicationContext;
    @Autowired JdbcTemplate jdbc;
    @Autowired SleepService sleep;
    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(applicationContext).apply(springSecurity()).build();
        for (String userId : List.of(USER_A, USER_B)) {
            jdbc.update("DELETE FROM sleep_record_tags WHERE sleep_record_id IN (SELECT id FROM sleep_records WHERE user_id=?)", userId);
            jdbc.update("DELETE FROM sleep_records WHERE user_id=?", userId);
            jdbc.update("DELETE FROM health_plan_versions WHERE plan_id IN (SELECT id FROM health_plans WHERE user_id=?)", userId);
            jdbc.update("DELETE FROM health_plans WHERE user_id=?", userId);
            jdbc.update("DELETE FROM health_profiles WHERE user_id=?", userId);
            jdbc.update("MERGE INTO users (id,phone,status) KEY(id) VALUES (?,?,'ACTIVE')", userId,
                    USER_A.equals(userId) ? "13000000121" : "13000000122");
            jdbc.update("INSERT INTO health_profiles (user_id,current_step,completed) VALUES (?,7,TRUE)", userId);
        }
    }

    @Test
    void requiresAuthenticationCreatesRetriesAndIsolatesUsers() throws Exception {
        mockMvc.perform(get("/api/v1/sleep/days/2026-09-09").param("timezone", "UTC"))
                .andExpect(status().isUnauthorized());
        String body = json("NIGHT", "2026-09-08T22:00:00Z", "2026-09-09T06:00:00Z", "UTC", 4);
        for (String userId : List.of(USER_A, USER_A, USER_B)) {
            mockMvc.perform(post("/api/v1/sleep/records").with(user(userId)).header("Idempotency-Key", "same")
                            .contentType(MediaType.APPLICATION_JSON).content(body))
                    .andExpect(status().isCreated()).andExpect(jsonPath("$.record.durationMinutes").value(480))
                    .andExpect(jsonPath("$.day.date").value("2026-09-09"));
        }
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM sleep_records WHERE idempotency_key='same'", Integer.class))
                .isEqualTo(2);
    }

    @Test
    void validatesRequestAndSupportsEditDeleteOwnership() throws Exception {
        String body = json("NAP", "2026-09-09T04:00:00Z", "2026-09-09T04:30:00Z", "UTC", null);
        mockMvc.perform(post("/api/v1/sleep/records").with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("IDEMPOTENCY_KEY_REQUIRED"));
        mockMvc.perform(get("/api/v1/sleep/days/2026-09-09").with(user(USER_A)))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.fieldErrors[0].field").value("timezone"));
        mockMvc.perform(get("/api/v1/sleep/weeks/bad").param("timezone", "UTC").with(user(USER_A)))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.fieldErrors[0].field").value("date"));

        mockMvc.perform(post("/api/v1/sleep/records").with(user(USER_A)).header("Idempotency-Key", "crud")
                        .contentType(MediaType.APPLICATION_JSON).content(body)).andExpect(status().isCreated());
        String id = jdbc.queryForObject("SELECT id FROM sleep_records WHERE user_id=?", String.class, USER_A);
        mockMvc.perform(put("/api/v1/sleep/records/{id}", id).with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json("NAP", "2026-09-09T03:30:00Z", "2026-09-09T04:30:00Z", "UTC", 5)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.record.durationMinutes").value(60))
                .andExpect(jsonPath("$.record.qualityLabel").value("很好"));
        mockMvc.perform(delete("/api/v1/sleep/records/{id}", id).param("timezone", "UTC").with(user(USER_B)))
                .andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("SLEEP_RECORD_NOT_FOUND"));
        mockMvc.perform(delete("/api/v1/sleep/records/{id}", id).param("timezone", "UTC").with(user(USER_A)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.day.status").value("EMPTY"));
    }

    @Test
    void returnsDayAndSevenDaySummariesByStableWakeDate() throws Exception {
        create(USER_A, "night", "NIGHT", "2026-09-08T23:30:00+08:00", "2026-09-09T07:00:00+08:00", "Asia/Shanghai");
        create(USER_A, "nap", "NAP", "2026-09-09T12:00:00+08:00", "2026-09-09T12:30:00+08:00", "+08:00");
        mockMvc.perform(get("/api/v1/sleep/days/2026-09-09").param("timezone", "Asia/Shanghai").with(user(USER_A)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.nightDurationMinutes").value(450))
                .andExpect(jsonPath("$.napDurationMinutes").value(30)).andExpect(jsonPath("$.records.length()").value(2));
        mockMvc.perform(get("/api/v1/sleep/weeks/2026-09-09").param("timezone", "+08:00").with(user(USER_A)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.startDate").value("2026-09-03"))
                .andExpect(jsonPath("$.endDate").value("2026-09-09"))
                .andExpect(jsonPath("$.averageNightDurationMinutes").value(450))
                .andExpect(jsonPath("$.napDurationMinutes").value(30))
                .andExpect(jsonPath("$.hasEnoughTrendData").value(false));
    }

    @Test
    void concurrentRetriesCreateOneRecord() throws Exception {
        var request = new SleepDtos.RecordRequest("NAP", OffsetDateTime.parse("2026-09-09T04:00:00Z"),
                OffsetDateTime.parse("2026-09-09T04:30:00Z"), "UTC", null, List.of(), null);
        var start = new CountDownLatch(1);
        var executor = Executors.newFixedThreadPool(6);
        try {
            List<Future<SleepDtos.MutationResponse>> futures = new ArrayList<>();
            for (int i = 0; i < 6; i++) futures.add(executor.submit(() -> {
                start.await();
                return sleep.create(USER_A, "concurrent", request);
            }));
            start.countDown();
            for (Future<SleepDtos.MutationResponse> future : futures)
                assertThat(future.get().day().records()).hasSize(1);
        } finally {
            executor.shutdownNow();
        }
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM sleep_records WHERE user_id=?", Integer.class, USER_A))
                .isEqualTo(1);
    }

    private void create(String userId, String key, String type, String start, String end, String zone) {
        sleep.create(userId, key, new SleepDtos.RecordRequest(type, OffsetDateTime.parse(start),
                OffsetDateTime.parse(end), zone, null, List.of(), null));
    }

    private String json(String type, String start, String end, String zone, Integer quality) {
        return """
                {"recordType":"%s","startedAt":"%s","endedAt":"%s","timezone":"%s",
                 "qualityScore":%s,"tags":["SCREEN_TIME"],"note":"测试备注"}
                """.formatted(type, start, end, zone, quality);
    }
}
