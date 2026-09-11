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

import com.lightbite.healthy.tasks.TaskDtos;
import com.lightbite.healthy.tasks.TaskService;
import java.time.LocalDate;
import java.time.ZoneOffset;
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
class TaskIntegrationTests {
    private static final String USER_A = "task-api-a";
    private static final String USER_B = "task-api-b";
    private static final LocalDate TODAY = LocalDate.now(ZoneOffset.UTC);
    @Autowired WebApplicationContext context;
    @Autowired JdbcTemplate jdbc;
    @Autowired TaskService tasks;
    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();
        jdbc.update("DELETE FROM task_notification_events");
        jdbc.update("DELETE FROM task_operation_keys");
        jdbc.update("DELETE FROM task_instances");
        jdbc.update("DELETE FROM task_templates");
        jdbc.update("DELETE FROM task_settings");
        for (String id : List.of(USER_A, USER_B)) {
            jdbc.update("DELETE FROM health_profiles WHERE user_id=?", id);
            jdbc.update("MERGE INTO users (id,phone,status) KEY(id) VALUES (?,?,'ACTIVE')", id,
                    USER_A.equals(id) ? "13000000931" : "13000000932");
        }
    }

    @Test
    void requiresAuthenticationCreatesAndKeepsUsersIsolated() throws Exception {
        mockMvc.perform(get("/api/v1/tasks/days/{date}", TODAY).param("timezone", "UTC"))
                .andExpect(status().isUnauthorized());
        String body = createJson("个人任务", "DAILY");
        for (String userId : List.of(USER_A, USER_A, USER_B)) {
            mockMvc.perform(post("/api/v1/tasks").with(user(userId)).header("Idempotency-Key", "same")
                            .contentType(MediaType.APPLICATION_JSON).content(body))
                    .andExpect(status().isCreated())
                    .andExpect(jsonPath("$.instances.length()").value(8));
        }
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM task_templates WHERE idempotency_key='same'",
                Integer.class)).isEqualTo(2);
        mockMvc.perform(get("/api/v1/tasks/days/{date}", TODAY).param("timezone", "UTC").with(user(USER_A)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("READY"))
                .andExpect(jsonPath("$.timeline[0].title").value("个人任务"));
    }

    @Test
    void exposesStateEditDeleteSettingsStatisticsAndEvents() throws Exception {
        mockMvc.perform(post("/api/v1/tasks").with(user(USER_A)).header("Idempotency-Key", "crud")
                        .contentType(MediaType.APPLICATION_JSON).content(createJson("接口任务", "NONE")))
                .andExpect(status().isCreated());
        String id = jdbc.queryForObject("SELECT id FROM task_instances WHERE user_id=?", String.class, USER_A);
        mockMvc.perform(post("/api/v1/tasks/instances/{id}/complete", id).with(user(USER_A))
                        .header("Idempotency-Key", "complete").param("timezone", "UTC"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("COMPLETED"));
        mockMvc.perform(post("/api/v1/tasks/instances/{id}/reopen", id).with(user(USER_A))
                        .header("Idempotency-Key", "reopen").param("timezone", "UTC"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("PENDING"));
        mockMvc.perform(post("/api/v1/tasks/instances/{id}/skip", id).with(user(USER_A))
                        .header("Idempotency-Key", "skip").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"reason\":\"今天不做\",\"timezone\":\"UTC\"}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("SKIPPED"));
        mockMvc.perform(delete("/api/v1/tasks/instances/{id}", id).with(user(USER_B)).param("timezone", "UTC"))
                .andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("TASK_NOT_FOUND"));

        mockMvc.perform(get("/api/v1/tasks/settings").with(user(USER_A)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.quietEnabled").value(true))
                .andExpect(jsonPath("$.quietStartTime").value("22:30"));
        mockMvc.perform(put("/api/v1/tasks/settings").with(user(USER_A)).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"quietEnabled\":false,\"quietStartTime\":\"23:00\","
                                + "\"quietEndTime\":\"06:00\",\"expectedVersion\":0}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.version").value(1));
        mockMvc.perform(get("/api/v1/tasks/weeks/{date}", TODAY).param("timezone", "UTC").with(user(USER_A)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.categories.length()").value(5));
        String hash = "a".repeat(64);
        mockMvc.perform(post("/api/v1/tasks/notification-events").with(user(USER_B))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"events\":[{\"instanceId\":\"" + id
                                + "\",\"deviceKeyHash\":\"" + hash + "\",\"eventType\":\"OPENED\","
                                + "\"idempotencyKey\":\"event-1\"}]}"))
                .andExpect(status().isNotFound());
    }

    @Test
    void concurrentCreateAndGenerationRemainUnique() throws Exception {
        var request = new TaskDtos.CreateRequest("并发任务", null, "WORK", "IMPORTANT", false, "18:00",
                TODAY, "DAILY", null, null, "UTC");
        var start = new CountDownLatch(1);
        var executor = Executors.newFixedThreadPool(6);
        try {
            List<Future<TaskDtos.CreateResponse>> creates = new ArrayList<>();
            for (int i = 0; i < 6; i++) creates.add(executor.submit(() -> {
                start.await();
                return tasks.create(USER_A, "concurrent-create", request);
            }));
            start.countDown();
            for (var result : creates) assertThat(result.get().instances()).hasSize(8);
            String template = jdbc.queryForObject("SELECT id FROM task_templates WHERE user_id=?", String.class, USER_A);
            jdbc.update("DELETE FROM task_instances WHERE template_id=? AND original_local_date=?", template,
                    TODAY.plusDays(1));
            var generationStart = new CountDownLatch(1);
            List<Future<?>> generations = new ArrayList<>();
            for (int i = 0; i < 6; i++) generations.add(executor.submit(() -> {
                generationStart.await();
                return tasks.day(USER_A, TODAY.plusDays(1), "UTC");
            }));
            generationStart.countDown();
            for (var result : generations) result.get();
            assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM task_instances WHERE template_id=? "
                    + "AND original_local_date=?", Integer.class, template, TODAY.plusDays(1))).isEqualTo(1);

            String instance = jdbc.queryForObject("SELECT id FROM task_instances WHERE template_id=? "
                    + "AND original_local_date=?", String.class, template, TODAY);
            int beforeVersion = jdbc.queryForObject("SELECT version FROM task_instances WHERE id=?",
                    Integer.class, instance);
            var operationStart = new CountDownLatch(1);
            List<Future<?>> operations = new ArrayList<>();
            for (int i = 0; i < 6; i++) operations.add(executor.submit(() -> {
                operationStart.await();
                return tasks.complete(USER_A, instance, "concurrent-complete", "UTC");
            }));
            operationStart.countDown();
            for (var result : operations) result.get();
            assertThat(jdbc.queryForObject("SELECT version FROM task_instances WHERE id=?", Integer.class, instance))
                    .isEqualTo(beforeVersion + 1);
            assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM task_operation_keys WHERE user_id=? "
                    + "AND idempotency_key='concurrent-complete'", Integer.class, USER_A)).isEqualTo(1);
        } finally {
            executor.shutdownNow();
        }
    }

    private String createJson(String title, String recurrence) {
        return """
                {"title":"%s","category":"WORK","priority":"IMPORTANT","allDay":false,
                 "localTime":"10:00","date":"%s","recurrenceType":"%s",
                 "reminderOffsetMinutes":15,"timezone":"UTC"}
                """.formatted(title, TODAY, recurrence);
    }
}
