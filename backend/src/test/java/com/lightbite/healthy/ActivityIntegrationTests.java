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

import com.lightbite.healthy.activity.ActivityDtos;
import com.lightbite.healthy.activity.ActivityService;
import java.math.BigDecimal;
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
class ActivityIntegrationTests {

    private static final String USER_A = "activity-api-a";
    private static final String USER_B = "activity-api-b";
    @Autowired WebApplicationContext applicationContext;
    @Autowired JdbcTemplate jdbc;
    @Autowired ActivityService activities;
    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(applicationContext).apply(springSecurity()).build();
        for (String userId : List.of(USER_A, USER_B)) {
            jdbc.update("DELETE FROM activity_records WHERE user_id=?", userId);
            jdbc.update("DELETE FROM activity_types WHERE owner_user_id=?", userId);
            jdbc.update("DELETE FROM health_plan_versions WHERE plan_id IN (SELECT id FROM health_plans WHERE user_id=?)", userId);
            jdbc.update("DELETE FROM health_plans WHERE user_id=?", userId);
            jdbc.update("DELETE FROM body_measurements WHERE user_id=?", userId);
            jdbc.update("DELETE FROM health_profiles WHERE user_id=?", userId);
            jdbc.update("MERGE INTO users (id,phone,status) KEY(id) VALUES (?,?,'ACTIVE')", userId,
                    USER_A.equals(userId) ? "13000000031" : "13000000032");
            jdbc.update("INSERT INTO health_profiles (user_id,current_step,completed) VALUES (?,7,TRUE)", userId);
            jdbc.update("INSERT INTO body_measurements (id,user_id,weight_kg,measured_at) VALUES (RANDOM_UUID(),?,?,CURRENT_TIMESTAMP)",
                    userId, new BigDecimal(USER_A.equals(userId) ? "60" : "80"));
        }
    }

    @Test
    void requiresAuthenticationAndSupportsTypesAndCustomTypes() throws Exception {
        mockMvc.perform(get("/api/v1/activity/types")).andExpect(status().isUnauthorized());
        mockMvc.perform(get("/api/v1/activity/types").param("query", "跑").with(user(USER_A)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].name").value("跑步"));

        String custom = "{\"name\":\"  室内快走  \",\"referenceTypeId\":\"act-walking\"}";
        mockMvc.perform(post("/api/v1/activity/types/custom").with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON).content(custom))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.name").value("室内快走"))
                .andExpect(jsonPath("$.typeScope").value("USER"));
        mockMvc.perform(post("/api/v1/activity/types/custom").with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON).content(custom))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("ACTIVITY_TYPE_NAME_EXISTS"));
        mockMvc.perform(get("/api/v1/activity/types").param("query", "室内").with(user(USER_B)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(0));
    }

    @Test
    void createsRetriesAndIsolatesTheSameIdempotencyKeyByUser() throws Exception {
        String body = recordJson("act-walking", "MEDIUM", 30,
                "2026-09-01T23:30:00+08:00", "Asia/Shanghai", "ESTIMATED", null);
        for (String userId : List.of(USER_A, USER_A, USER_B)) {
            mockMvc.perform(post("/api/v1/activity/records").with(user(userId))
                            .header("Idempotency-Key", "shared-key")
                            .contentType(MediaType.APPLICATION_JSON).content(body))
                    .andExpect(status().isCreated())
                    .andExpect(jsonPath("$.day.date").value("2026-09-01"))
                    .andExpect(jsonPath("$.day.recordCount").value(1));
        }
        assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM activity_records WHERE idempotency_key='shared-key'", Integer.class))
                .isEqualTo(2);
    }

    @Test
    void createsEditsRestoresDeletesAndHidesOwnership() throws Exception {
        mockMvc.perform(post("/api/v1/activity/records").with(user(USER_A))
                        .header("Idempotency-Key", "crud-key")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(recordJson("act-running", "LOW", 30, "2026-09-01T10:00:00Z", "UTC",
                                "USER_OVERRIDE", 300)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.record.estimatedKcal").value(180))
                .andExpect(jsonPath("$.record.finalKcal").value(300))
                .andExpect(jsonPath("$.record.calorieSource").value("USER_OVERRIDE"));
        String id = jdbc.queryForObject(
                "SELECT id FROM activity_records WHERE user_id=? AND idempotency_key='crud-key'", String.class, USER_A);

        mockMvc.perform(put("/api/v1/activity/records/{id}", id).with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(recordJson("act-running", "MEDIUM", 60, "2026-09-01T11:00:00Z", "UTC",
                                "RESTORE_ESTIMATED", null)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.record.finalKcal").value(498))
                .andExpect(jsonPath("$.record.calorieSource").value("ESTIMATED"));
        mockMvc.perform(delete("/api/v1/activity/records/{id}", id).param("timezone", "UTC").with(user(USER_B)))
                .andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("ACTIVITY_RECORD_NOT_FOUND"));
        mockMvc.perform(delete("/api/v1/activity/records/{id}", id).param("timezone", "UTC").with(user(USER_A)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.day.status").value("EMPTY"));
        mockMvc.perform(delete("/api/v1/activity/records/{id}", id).param("timezone", "UTC").with(user(USER_A)))
                .andExpect(status().isNotFound());
    }

    @Test
    void validatesRequiredHeaderDateTimezoneAndFutureTime() throws Exception {
        String valid = recordJson("act-walking", "LOW", 30,
                "2026-09-01T08:00:00Z", "UTC", "ESTIMATED", null);
        mockMvc.perform(post("/api/v1/activity/records").with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON).content(valid))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("IDEMPOTENCY_KEY_REQUIRED"));
        mockMvc.perform(get("/api/v1/activity/days/2026-09-01").with(user(USER_A)))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.fieldErrors[0].field").value("timezone"));
        mockMvc.perform(get("/api/v1/activity/weeks/not-a-date").param("timezone", "UTC").with(user(USER_A)))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.fieldErrors[0].field").value("date"));
        mockMvc.perform(get("/api/v1/activity/days/2026-09-01").param("timezone", "Mars/Base").with(user(USER_A)))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("INVALID_TIMEZONE"));
        mockMvc.perform(post("/api/v1/activity/records").with(user(USER_A))
                        .header("Idempotency-Key", "future-key").contentType(MediaType.APPLICATION_JSON)
                        .content(recordJson("act-walking", "LOW", 30, "2099-01-01T00:00:00Z", "UTC",
                                "ESTIMATED", null)))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("FUTURE_TIME_NOT_ALLOWED"));
    }

    @Test
    void aggregatesAcrossMidnightAndMondayBoundary() throws Exception {
        create(USER_A, "sunday", "2026-09-06T15:30:00Z", "Asia/Shanghai", 15);
        create(USER_A, "monday-one", "2026-09-06T16:30:00Z", "Asia/Shanghai", 30);
        create(USER_A, "monday-two", "2026-09-07T01:00:00+08:00", "Asia/Shanghai", 45);

        mockMvc.perform(get("/api/v1/activity/days/2026-09-07")
                        .param("timezone", "Asia/Shanghai").with(user(USER_A)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.recordCount").value(2))
                .andExpect(jsonPath("$.totalDurationMinutes").value(75));
        mockMvc.perform(get("/api/v1/activity/weeks/2026-09-07")
                        .param("timezone", "+08:00").with(user(USER_A)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.startDate").value("2026-09-07"))
                .andExpect(jsonPath("$.endDate").value("2026-09-13"))
                .andExpect(jsonPath("$.exerciseDays").value(1))
                .andExpect(jsonPath("$.durationMinutes").value(75))
                .andExpect(jsonPath("$.targetExerciseDays").doesNotExist())
                .andExpect(jsonPath("$.planState").value("NO_PLAN"));
    }

    @Test
    void concurrentRetriesCreateOneRecord() throws Exception {
        var request = new ActivityDtos.RecordRequest("act-walking", "LOW", 30,
                OffsetDateTime.parse("2026-09-01T08:00:00Z"), "UTC", "ESTIMATED", null);
        var start = new CountDownLatch(1);
        var executor = Executors.newFixedThreadPool(6);
        try {
            List<Future<ActivityDtos.MutationResponse>> futures = new ArrayList<>();
            for (int index = 0; index < 6; index++) {
                futures.add(executor.submit(() -> {
                    start.await();
                    return activities.create(USER_A, "concurrent-key", request);
                }));
            }
            start.countDown();
            for (Future<ActivityDtos.MutationResponse> future : futures) {
                assertThat(future.get().day().recordCount()).isEqualTo(1);
            }
        } finally {
            executor.shutdownNow();
        }
        assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM activity_records WHERE user_id=? AND idempotency_key=?",
                Integer.class, USER_A, "concurrent-key")).isEqualTo(1);
    }

    private void create(String userId, String key, String occurredAt, String timezone, int minutes) {
        activities.create(userId, key, new ActivityDtos.RecordRequest("act-walking", "LOW", minutes,
                OffsetDateTime.parse(occurredAt), timezone, "ESTIMATED", null));
    }

    private String recordJson(String type, String intensity, int minutes, String occurredAt,
                              String timezone, String mode, Integer finalKcal) {
        return "{\"activityTypeId\":\"%s\",\"intensity\":\"%s\",\"durationMinutes\":%d,"
                .formatted(type, intensity, minutes)
                + "\"occurredAt\":\"%s\",\"timezone\":\"%s\",\"calorieMode\":\"%s\",\"finalKcal\":%s}"
                .formatted(occurredAt, timezone, mode, finalKcal);
    }
}
