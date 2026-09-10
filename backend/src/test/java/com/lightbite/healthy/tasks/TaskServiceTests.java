package com.lightbite.healthy.tasks;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;

import com.lightbite.healthy.common.api.ApiException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;

class TaskServiceTests {
    private static final String USER = "task-user";
    private static final Instant NOW = Instant.parse("2026-09-10T04:00:00Z");
    private JdbcTemplate jdbc;
    private TaskService service;

    @BeforeEach
    void setUp() {
        var dataSource = new SingleConnectionDataSource("jdbc:h2:mem:task_service_"
                + UUID.randomUUID().toString().replace("-", "")
                + ";MODE=MySQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1", "sa", "", true);
        Flyway.configure().dataSource(dataSource).load().migrate();
        jdbc = new JdbcTemplate(dataSource);
        jdbc.update("INSERT INTO users (id,phone,status) VALUES (?,?,'ACTIVE')", USER, "13000000911");
        TaskHealthLinkService links = mock(TaskHealthLinkService.class);
        service = new TaskService(jdbc, new TaskSchedulePolicy(), links, Clock.fixed(NOW, ZoneOffset.UTC));
    }

    @Test
    void createsRepeatTemplateGeneratesEightDaysAndRetriesIdempotently() {
        var created = service.create(USER, "create-key", request("每日整理", false, "03:30", "DAILY", null));
        var retried = service.create(USER, "create-key", request("不同内容", true, null, "NONE", null));
        assertThat(retried.templateId()).isEqualTo(created.templateId());
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM task_instances WHERE template_id=?",
                Integer.class, created.templateId())).isEqualTo(8);

        var day = service.day(USER, LocalDate.of(2026, 9, 10), "Asia/Shanghai");
        assertThat(day.timeline()).extracting(TaskDtos.InstanceResponse::title).containsExactly("每日整理");
        assertThat(day.summary().totalCount()).isEqualTo(1);
        assertThat(day.summary().overdueCount()).isEqualTo(1);
        assertThat(service.day(USER, LocalDate.of(2026, 9, 10), "Asia/Shanghai").timeline()).hasSize(1);
        service.day(USER, LocalDate.of(2026, 9, 9), "Asia/Shanghai");
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM task_instances WHERE template_id=?",
                Integer.class, created.templateId())).isEqualTo(8);
    }

    @Test
    void validatesFieldsReminderRuleAndFutureRange() {
        assertField("title", () -> service.create(USER, "blank", request("  ", true, null, "NONE", null)));
        assertField("note", () -> service.create(USER, "note", new TaskDtos.CreateRequest("任务", "字".repeat(501),
                "LIFE", "NORMAL", true, null, LocalDate.of(2026, 9, 10), "NONE", null, null, "UTC")));
        assertField("category", () -> service.create(USER, "category", new TaskDtos.CreateRequest("任务", null,
                "BAD", "NORMAL", true, null, LocalDate.of(2026, 9, 10), "NONE", null, null, "UTC")));
        assertField("localTime", () -> service.create(USER, "gap", new TaskDtos.CreateRequest("任务", null,
                "LIFE", "NORMAL", false, "02:30", LocalDate.of(2026, 3, 8), "NONE", null, 5,
                "America/New_York")));
        assertField("reminderOffsetMinutes", () -> service.create(USER, "reminder",
                request("任务", true, null, "NONE", 15)));
        assertField("Idempotency-Key", () -> service.create(USER, null, request("任务", true, null, "NONE", null)));
        assertField("date", () -> service.day(USER, LocalDate.of(2026, 9, 18), "UTC"));
    }

    @Test
    void completesSkipsReopensAndKeepsOperationKeysPerUser() {
        String id = service.create(USER, "one", request("状态任务", true, null, "NONE", null)).instances().get(0).id();
        assertThat(service.complete(USER, id, "complete", "UTC").status()).isEqualTo("COMPLETED");
        assertThat(service.complete(USER, id, "complete", "UTC").completionSource()).isEqualTo("USER");
        assertThat(service.reopen(USER, id, "reopen", "UTC").status()).isEqualTo("PENDING");
        assertThat(service.skip(USER, id, "skip", "暂不处理", "UTC").status()).isEqualTo("SKIPPED");
        assertThat(service.skip(USER, id, "skip", "不同原因", "UTC").skipReason()).isEqualTo("暂不处理");
        assertThat(service.reopen(USER, id, "reopen-2", "UTC").status()).isEqualTo("PENDING");
        assertField("Idempotency-Key", () -> service.complete(USER, id, null, "UTC"));
        assertCode("TASK_NOT_FOUND", () -> service.complete("other", id, "other", "UTC"));
    }

    @Test
    void returnsTemplateMetadataSeparatelyAfterInstanceStateChanges() {
        var created = service.create(USER, "template-version",
                request("重复安排", false, "09:00", "DAILY", null));
        var completed = service.complete(USER, created.instances().get(0).id(), "complete-version", "UTC");

        assertThat(completed.version()).isEqualTo(1);
        assertThat(completed.templateVersion()).isEqualTo(created.version());
        assertThat(completed.recurrenceType()).isEqualTo("DAILY");
        assertThat(completed.weekdays()).isEmpty();
        service.updateTemplate(USER, created.templateId(), new TaskDtos.TemplateUpdateRequest("新的安排", null,
                "LIFE", "NORMAL", false, "10:00", "DAILY", null, null,
                LocalDate.of(2026, 9, 10), completed.templateVersion(), "UTC"));
    }

    @Test
    void postponesCustomLocalDateAndTimeInTheRequestedTimezone() {
        var created = service.create(USER, "custom-local-time",
                request("自选延期", false, "09:00", "NONE", null));

        var postponed = service.postpone(USER, created.instances().get(0).id(), "custom-local-key",
                new TaskDtos.PostponeRequest("CUSTOM", null, LocalDate.of(2026, 9, 12), "10:30",
                        "Asia/Shanghai"));

        assertThat(postponed.currentLocalDate()).isEqualTo(LocalDate.of(2026, 9, 12));
        assertThat(postponed.currentDueAt()).isEqualTo(Instant.parse("2026-09-12T02:30:00Z"));
    }

    @Test
    void customPostponeTurnsAnAllDayInstanceIntoATimedInstance() {
        var created = service.create(USER, "custom-all-day",
                request("全天自选延期", true, null, "NONE", null));

        var postponed = service.postpone(USER, created.instances().get(0).id(), "custom-all-day-key",
                new TaskDtos.PostponeRequest("CUSTOM", null, LocalDate.of(2026, 9, 12), "10:30",
                        "Asia/Shanghai"));

        assertThat(postponed.allDay()).isFalse();
        assertThat(postponed.localTime()).isEqualTo("10:30");
        assertThat(postponed.currentLocalDate()).isEqualTo(LocalDate.of(2026, 9, 12));
        assertThat(postponed.currentDueAt()).isEqualTo(Instant.parse("2026-09-12T02:30:00Z"));
    }

    @Test
    void postponesEditsAndDeletesOnlyRequestedScopeWithVersionChecks() {
        var created = service.create(USER, "repeat", request("原任务", false, "09:00", "DAILY", null));
        var first = created.instances().get(0);
        var completed = service.complete(USER, created.instances().get(1).id(), "keep-completed", "UTC");
        var skipped = service.skip(USER, created.instances().get(2).id(), "keep-skipped", null, "UTC");
        var later = service.postpone(USER, first.id(), "later", new TaskDtos.PostponeRequest("LATER", null, "UTC"));
        assertThat(later.postponeCount()).isEqualTo(1);
        assertThat(later.currentDueAt()).isEqualTo(first.currentDueAt().plusSeconds(1800));
        var tomorrow = service.postpone(USER, first.id(), "tomorrow", new TaskDtos.PostponeRequest("TOMORROW", null, "UTC"));
        assertThat(tomorrow.currentLocalDate()).isEqualTo(first.originalLocalDate().plusDays(1));
        var custom = service.postpone(USER, first.id(), "custom", new TaskDtos.PostponeRequest("CUSTOM",
                OffsetDateTime.parse("2026-09-12T10:00:00Z"), "UTC"));
        assertThat(custom.postponeCount()).isEqualTo(3);

        service.updateInstance(USER, first.id(), new TaskDtos.InstanceUpdateRequest("仅今天", null, "WORK",
                "URGENT", false, "10:00", null, first.version() + 3, "UTC"));
        assertThat(service.day(USER, LocalDate.of(2026, 9, 12), "UTC").timeline())
                .extracting(TaskDtos.InstanceResponse::title).contains("仅今天");
        assertThat(jdbc.queryForObject("SELECT title FROM task_templates WHERE id=?", String.class,
                created.templateId())).isEqualTo("原任务");

        assertCode("TASK_VERSION_CONFLICT", () -> service.updateTemplate(USER, created.templateId(),
                new TaskDtos.TemplateUpdateRequest("新安排", null, "LIFE", "NORMAL", false, "11:00", "DAILY",
                        null, null, LocalDate.of(2026, 9, 10), 99, "UTC")));
        int version = jdbc.queryForObject("SELECT version FROM task_templates WHERE id=?", Integer.class,
                created.templateId());
        service.updateTemplate(USER, created.templateId(), new TaskDtos.TemplateUpdateRequest("新安排", null,
                "LIFE", "NORMAL", false, "11:00", "DAILY", null, null,
                LocalDate.of(2026, 9, 10), version, "UTC"));
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM task_instances WHERE template_id=? AND title='新安排'",
                Integer.class, created.templateId())).isGreaterThan(0);
        assertThat(service.day(USER, completed.originalLocalDate(), "UTC").completed())
                .extracting(TaskDtos.InstanceResponse::title).containsExactly("原任务");
        assertThat(service.day(USER, skipped.originalLocalDate(), "UTC").skipped())
                .extracting(TaskDtos.InstanceResponse::title).containsExactly("原任务");

        String onlyToday = service.create(USER, "delete-one", request("单独删除", true, null, "NONE", null))
                .instances().get(0).id();
        service.deleteInstance(USER, onlyToday, "UTC");
        assertCode("TASK_NOT_FOUND", () -> service.deleteInstance(USER, onlyToday, "UTC"));
        service.deleteTemplate(USER, created.templateId(), LocalDate.of(2026, 9, 12), "UTC");
        assertThat(jdbc.queryForObject("SELECT disabled_from FROM task_templates WHERE id=?", LocalDate.class,
                created.templateId())).isEqualTo(LocalDate.of(2026, 9, 12));
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM task_instances WHERE id IN (?,?) AND deleted_at IS NULL",
                Integer.class, completed.id(), skipped.id())).isEqualTo(2);
        assertThat(jdbc.queryForObject("SELECT deleted_at FROM task_instances WHERE id=?", Instant.class,
                first.id())).isNull();
        assertCode("TASK_NOT_FOUND", () -> service.deleteInstance("other", first.id(), "UTC"));
    }

    @Test
    void appliesQuietHoursAcceptsOnlyHashedIdempotentEventsAndKeepsWeekDenominatorStable() {
        String id = service.create(USER, "quiet", request("夜间提醒", false, "23:00", "NONE", 15))
                .instances().get(0).id();
        assertThat(service.notifications(USER, LocalDate.of(2026, 9, 10),
                LocalDate.of(2026, 9, 10), "UTC")).isEmpty();
        var settings = service.settings(USER);
        service.updateSettings(USER, new TaskDtos.SettingsRequest(false, "22:30", "07:00", settings.version()));
        assertThat(service.notifications(USER, LocalDate.of(2026, 9, 10),
                LocalDate.of(2026, 9, 10), "UTC")).hasSize(1);

        String hash = "a".repeat(64);
        var events = new TaskDtos.NotificationEventsRequest(List.of(
                event(id, hash, "SCHEDULED", "scheduled"),
                event(id, hash, "CANCELLED", "cancelled"),
                event(id, hash, "OPENED", "opened")));
        assertThat(service.notificationEvents(USER, events).acceptedCount()).isEqualTo(3);
        assertThat(service.notificationEvents(USER, events).acceptedCount()).isZero();
        assertField("deviceKeyHash", () -> service.notificationEvents(USER,
                new TaskDtos.NotificationEventsRequest(List.of(event(id, "raw-device", "OPENED", "raw")))));
        assertField("eventType", () -> service.notificationEvents(USER,
                new TaskDtos.NotificationEventsRequest(List.of(event(id, hash, "BAD", "bad")))));

        service.postpone(USER, id, "postpone-1", new TaskDtos.PostponeRequest("LATER", null, "UTC"));
        service.postpone(USER, id, "postpone-2", new TaskDtos.PostponeRequest("LATER", null, "UTC"));
        assertThat(service.week(USER, LocalDate.of(2026, 9, 10), "UTC").postponedCount()).isEqualTo(1);
        service.deleteInstance(USER, id, "UTC");
        var empty = service.week(USER, LocalDate.of(2026, 9, 10), "UTC");
        assertThat(empty.totalCount()).isZero();
        assertThat(empty.completionRate()).isNull();
    }

    @Test
    void settingsNotificationsWeekAndTodayUseRealTaskState() {
        var settings = service.settings(USER);
        assertThat(settings.quietEnabled()).isTrue();
        assertThat(settings.quietStartTime()).isEqualTo("22:30");
        assertThat(settings.quietEndTime()).isEqualTo("07:00");
        var changed = service.updateSettings(USER,
                new TaskDtos.SettingsRequest(false, "23:00", "06:00", settings.version()));
        assertThat(changed.quietEnabled()).isFalse();
        assertCode("TASK_VERSION_CONFLICT", () -> service.updateSettings(USER,
                new TaskDtos.SettingsRequest(true, "22:00", "07:00", settings.version())));

        String timed = service.create(USER, "notify", request("提醒任务", false, "15:00", "NONE", 15))
                .instances().get(0).id();
        service.create(USER, "all-day", request("全天任务", true, null, "NONE", null));
        assertThat(service.notifications(USER, LocalDate.of(2026, 9, 10), LocalDate.of(2026, 9, 17), "UTC"))
                .extracting(TaskDtos.NotificationResponse::instanceId).containsExactly(timed);

        service.complete(USER, timed, "done", "UTC");
        var week = service.week(USER, LocalDate.of(2026, 9, 10), "UTC");
        assertThat(week.totalCount()).isEqualTo(2);
        assertThat(week.completedCount()).isEqualTo(1);
        assertThat(week.completionRate()).isEqualByComparingTo("0.5000");
        assertThat(week.userCompletedCount()).isEqualTo(1);
        assertThat(week.autoCompletedCount()).isZero();
        assertThat(week.categories()).hasSize(5);
        var today = service.todaySummary(USER, LocalDate.of(2026, 9, 10), "UTC");
        assertThat(today.status()).isEqualTo("READY");
        assertThat(today.pendingCount()).isEqualTo(1);
        assertThat(today.nextTask().title()).isEqualTo("全天任务");
    }

    @Test
    void schedulesEverySupportedReminderOffset() {
        var settings = service.settings(USER);
        service.updateSettings(USER, new TaskDtos.SettingsRequest(false, "22:30", "07:00", settings.version()));
        for (int offset : List.of(0, 5, 15, 30, 60)) {
            service.create(USER, "reminder-" + offset,
                    request("提前" + offset + "分钟", false, "15:00", "NONE", offset));
        }
        var notifications = service.notifications(USER, LocalDate.of(2026, 9, 10),
                LocalDate.of(2026, 9, 10), "UTC");
        assertThat(notifications).hasSize(5);
        assertThat(notifications).allSatisfy(notification -> assertThat(
                notification.dueAt().getEpochSecond() - notification.notifyAt().getEpochSecond())
                .isIn(0L, 300L, 900L, 1800L, 3600L));
    }

    private TaskDtos.CreateRequest request(String title, boolean allDay, String time, String recurrence,
                                           Integer reminder) {
        return new TaskDtos.CreateRequest(title, null, "LIFE", "NORMAL", allDay, time,
                LocalDate.of(2026, 9, 10), recurrence, null, reminder, "UTC");
    }

    private TaskDtos.NotificationEventRequest event(String instanceId, String hash, String type, String key) {
        return new TaskDtos.NotificationEventRequest(instanceId, hash, type, null, NOW, key);
    }

    private void assertField(String field, org.assertj.core.api.ThrowableAssert.ThrowingCallable call) {
        assertThatThrownBy(call).isInstanceOfSatisfying(ApiException.class,
                error -> assertThat(error.fieldErrors()).extracting("field").contains(field));
    }

    private void assertCode(String code, org.assertj.core.api.ThrowableAssert.ThrowingCallable call) {
        assertThatThrownBy(call).isInstanceOfSatisfying(ApiException.class,
                error -> assertThat(error.code()).isEqualTo(code));
    }
}
