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

import com.lightbite.healthy.hydration.HydrationDtos;
import com.lightbite.healthy.hydration.HydrationService;
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
class HydrationIntegrationTests {

    private static final String USER_A = "hydration-api-a";
    private static final String USER_B = "hydration-api-b";

    @Autowired WebApplicationContext applicationContext;
    @Autowired JdbcTemplate jdbc;
    @Autowired HydrationService hydration;
    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(applicationContext).apply(springSecurity()).build();
        for (String userId : List.of(USER_A, USER_B)) {
            jdbc.update("DELETE FROM hydration_entries WHERE user_id=?", userId);
            jdbc.update("DELETE FROM hydration_settings WHERE user_id=?", userId);
            jdbc.update("DELETE FROM health_plan_versions WHERE plan_id IN (SELECT id FROM health_plans WHERE user_id=?)", userId);
            jdbc.update("DELETE FROM health_plans WHERE user_id=?", userId);
            jdbc.update("DELETE FROM health_profiles WHERE user_id=?", userId);
            jdbc.update("MERGE INTO users (id,phone,status) KEY(id) VALUES (?,?,'ACTIVE')", userId,
                    USER_A.equals(userId) ? "13000000021" : "13000000022");
            jdbc.update("INSERT INTO health_profiles (user_id,current_step,completed) VALUES (?,7,TRUE)", userId);
        }
    }

    @Test
    void requiresAuthenticationAndReturnsDefaultSettings() throws Exception {
        mockMvc.perform(get("/api/v1/hydration/settings"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/api/v1/hydration/settings").with(user(USER_A)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.effectiveTargetMl").value(2000))
                .andExpect(jsonPath("$.defaultCupMl").value(250))
                .andExpect(jsonPath("$.targetSource").value("DEFAULT"))
                .andExpect(jsonPath("$.version").value(0));
    }

    @Test
    void updatesSettingsWithFieldErrorsAndVersionConflict() throws Exception {
        mockMvc.perform(put("/api/v1/hydration/settings").with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON).content(settingsJson(525, 250, 0)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("INVALID_DAILY_TARGET"))
                .andExpect(jsonPath("$.fieldErrors[0].field").value("dailyTargetMl"))
                .andExpect(jsonPath("$.fieldErrors[0].message").isNotEmpty());

        mockMvc.perform(put("/api/v1/hydration/settings").with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON).content(settingsJson(null, 300, 0)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.dailyTargetMl").doesNotExist())
                .andExpect(jsonPath("$.effectiveTargetMl").value(2000))
                .andExpect(jsonPath("$.targetSource").value("DEFAULT"))
                .andExpect(jsonPath("$.version").value(1));

        mockMvc.perform(put("/api/v1/hydration/settings").with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON).content(settingsJson(2200, 300, 1)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.effectiveTargetMl").value(2200))
                .andExpect(jsonPath("$.targetSource").value("USER"))
                .andExpect(jsonPath("$.version").value(2));

        mockMvc.perform(put("/api/v1/hydration/settings").with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON).content(settingsJson(null, 400, 2)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.dailyTargetMl").value(2200))
                .andExpect(jsonPath("$.targetSource").value("USER"))
                .andExpect(jsonPath("$.defaultCupMl").value(400))
                .andExpect(jsonPath("$.version").value(3));

        mockMvc.perform(put("/api/v1/hydration/settings").with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON).content(settingsJson(2300, 300, 0)))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("HYDRATION_SETTINGS_VERSION_CONFLICT"))
                .andExpect(jsonPath("$.message").value("饮水设置已更新，请刷新后重试"));
    }

    @Test
    void createsRetriesAndIsolatesIdempotencyKeysByUser() throws Exception {
        String body = entryJson(250, "2026-09-01T23:30:00+08:00", "Asia/Shanghai", "QUICK");
        for (String userId : List.of(USER_A, USER_A, USER_B)) {
            mockMvc.perform(post("/api/v1/hydration/entries").with(user(userId))
                            .header("Idempotency-Key", "shared-key")
                            .contentType(MediaType.APPLICATION_JSON).content(body))
                    .andExpect(status().isCreated())
                    .andExpect(jsonPath("$.date").value("2026-09-01"))
                    .andExpect(jsonPath("$.totalMl").value(250))
                    .andExpect(jsonPath("$.entries.length()").value(1));
        }
        assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM hydration_entries WHERE idempotency_key='shared-key'", Integer.class))
                .isEqualTo(2);
    }

    @Test
    void validatesHeadersTimezoneAndCapacity() throws Exception {
        String valid = entryJson(250, "2026-09-01T08:00:00Z", "UTC", "CUSTOM");
        mockMvc.perform(post("/api/v1/hydration/entries").with(user(USER_A))
                        .contentType(MediaType.APPLICATION_JSON).content(valid))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("IDEMPOTENCY_KEY_REQUIRED"));
        mockMvc.perform(post("/api/v1/hydration/entries").with(user(USER_A))
                        .header("Idempotency-Key", "invalid-amount")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(entryJson(3001, "2026-09-01T08:00:00Z", "UTC", "CUSTOM")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.fieldErrors[0].field").value("amountMl"));
        mockMvc.perform(get("/api/v1/hydration/days/2026-09-01").with(user(USER_A)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.fieldErrors[0].field").value("timezone"));
        mockMvc.perform(get("/api/v1/hydration/days/2026-09-01?timezone=Mars/Base").with(user(USER_A)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.fieldErrors[0].field").value("timezone"));
    }

    @Test
    void readsByLocalDateAndHidesDeleteOwnership() throws Exception {
        String body = entryJson(300, "2026-09-01T16:30:00Z", "Asia/Shanghai", "PRESET");
        mockMvc.perform(post("/api/v1/hydration/entries").with(user(USER_A))
                        .header("Idempotency-Key", "midnight-key")
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.date").value("2026-09-02"));
        String id = jdbc.queryForObject(
                "SELECT id FROM hydration_entries WHERE user_id=?", String.class, USER_A);

        mockMvc.perform(get("/api/v1/hydration/days/2026-09-02?timezone=Asia/Shanghai").with(user(USER_A)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.totalMl").value(300));
        mockMvc.perform(get("/api/v1/hydration/days/2026-09-01?timezone=Asia/Shanghai").with(user(USER_A)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.totalMl").value(0));
        mockMvc.perform(delete("/api/v1/hydration/entries/{id}?timezone=Asia/Shanghai", id).with(user(USER_B)))
                .andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("HYDRATION_ENTRY_NOT_FOUND"));
        mockMvc.perform(delete("/api/v1/hydration/entries/{id}?timezone=Asia/Shanghai", id).with(user(USER_A)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("EMPTY"));
        mockMvc.perform(delete("/api/v1/hydration/entries/{id}?timezone=Asia/Shanghai", id).with(user(USER_A)))
                .andExpect(status().isNotFound());
    }

    @Test
    void concurrentRetriesCreateOneEntry() throws Exception {
        var request = new HydrationDtos.EntryRequest(250,
                OffsetDateTime.parse("2026-09-01T08:00:00Z"), "UTC", "QUICK");
        var start = new CountDownLatch(1);
        var executor = Executors.newFixedThreadPool(6);
        try {
            List<Future<HydrationDtos.DayResponse>> futures = new ArrayList<>();
            for (int index = 0; index < 6; index++) {
                futures.add(executor.submit(() -> {
                    start.await();
                    return hydration.create(USER_A, "concurrent-key", request);
                }));
            }
            start.countDown();
            for (Future<HydrationDtos.DayResponse> future : futures) {
                assertThat(future.get().totalMl()).isEqualTo(250);
            }
        } finally {
            executor.shutdownNow();
        }
        assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM hydration_entries WHERE user_id=? AND idempotency_key=?",
                Integer.class, USER_A, "concurrent-key")).isEqualTo(1);
    }

    @Test
    void rejectsWritesForIncompleteProfile() throws Exception {
        jdbc.update("UPDATE health_profiles SET completed=FALSE WHERE user_id=?", USER_A);
        mockMvc.perform(post("/api/v1/hydration/entries").with(user(USER_A))
                        .header("Idempotency-Key", "profile-key")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(entryJson(250, "2026-09-01T08:00:00Z", "UTC", "QUICK")))
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("PROFILE_INCOMPLETE"));
    }

    private String settingsJson(Integer target, int cup, int version) {
        return """
                {"dailyTargetMl":%d,"defaultCupMl":%d,"reminderEnabled":false,
                 "reminderStartTime":"08:00","reminderEndTime":"22:00",
                 "reminderIntervalMinutes":120,"quietStartTime":null,"quietEndTime":null,"version":%d}
                """.formatted(target, cup, version);
    }

    private String entryJson(int amount, String occurredAt, String timezone, String source) {
        return """
                {"amountMl":%d,"occurredAt":"%s","timezone":"%s","source":"%s"}
                """.formatted(amount, occurredAt, timezone, source);
    }
}
