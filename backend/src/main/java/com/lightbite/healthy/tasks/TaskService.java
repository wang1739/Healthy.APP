package com.lightbite.healthy.tasks;

import com.lightbite.healthy.common.api.ApiException;
import com.lightbite.healthy.common.api.ApiFieldError;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Time;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class TaskService {
    private static final Set<String> CATEGORIES = Set.of("HEALTH", "WORK", "LIFE", "STUDY", "OTHER");
    private static final Set<String> PRIORITIES = Set.of("NORMAL", "IMPORTANT", "URGENT");
    private static final Set<Integer> REMINDERS = Set.of(0, 5, 15, 30, 60);
    private static final List<String> CATEGORY_ORDER = List.of("HEALTH", "WORK", "LIFE", "STUDY", "OTHER");
    private final JdbcTemplate jdbc;
    private final TaskSchedulePolicy schedule;
    private final TaskHealthLinkService healthLinks;
    private final Clock clock;

    @Autowired
    public TaskService(JdbcTemplate jdbc, TaskSchedulePolicy schedule, TaskHealthLinkService healthLinks) {
        this(jdbc, schedule, healthLinks, Clock.systemUTC());
    }

    TaskService(JdbcTemplate jdbc, TaskSchedulePolicy schedule, TaskHealthLinkService healthLinks, Clock clock) {
        this.jdbc = jdbc;
        this.schedule = schedule;
        this.healthLinks = healthLinks;
        this.clock = clock;
    }

    @Transactional
    public TaskDtos.CreateResponse create(String userId, String idempotencyKey, TaskDtos.CreateRequest request) {
        String key = key(idempotencyKey);
        List<String> existing = jdbc.query("SELECT id FROM task_templates WHERE user_id=? AND idempotency_key=?",
                (rs, row) -> rs.getString(1), userId, key);
        if (!existing.isEmpty()) return createResponse(userId, existing.get(0));
        Values values = validate(request);
        String templateId = UUID.randomUUID().toString();
        try {
            jdbc.update("""
                    INSERT INTO task_templates
                    (id,user_id,source,title,note,category,priority,all_day,local_time,recurrence_type,weekdays_mask,
                     reminder_offset_minutes,effective_from,user_overridden,version,idempotency_key,created_at,updated_at)
                    VALUES (?,?,'USER',?,?,?,?,?,?,?,?,?,?,FALSE,0,?,?,?)
                    """, templateId, userId, values.title(), values.note(), values.category(), values.priority(),
                    values.allDay(), time(values.time()), values.recurrence(), values.weekdaysMask(), values.reminder(),
                    values.date(), key, now(), now());
        } catch (DataIntegrityViolationException exception) {
            List<String> raced = jdbc.query("SELECT id FROM task_templates WHERE user_id=? AND idempotency_key=?",
                    (rs, row) -> rs.getString(1), userId, key);
            if (raced.isEmpty()) throw exception;
            templateId = raced.get(0);
        }
        LocalDate today = today(values.zone());
        for (LocalDate date = today; !date.isAfter(today.plusDays(7)); date = date.plusDays(1)) {
            generate(templateId, userId, date, values.zone());
        }
        return createResponse(userId, templateId);
    }

    @Transactional
    public TaskDtos.DayResponse day(String userId, LocalDate date, String timezone) {
        ZoneId zone = schedule.zone(timezone);
        LocalDate today = today(zone);
        if (schedule.shouldEnsure(date, today)) {
            healthLinks.ensurePlanTemplates(userId, date, zone.getId());
            ensureInstances(userId, date, zone);
        }
        healthLinks.reconcile(userId, date, zone.getId());
        String healthGuide = healthLinks.healthGuide(userId);
        List<TaskDtos.InstanceResponse> all = instances(userId, "i.current_local_date=? AND i.deleted_at IS NULL", date);
        if ("COMPLETE_PROFILE".equals(healthGuide)) {
            all = all.stream().filter(i -> "USER".equals(i.source())).toList();
        }
        List<TaskDtos.InstanceResponse> completed = all.stream().filter(i -> "COMPLETED".equals(i.status())).toList();
        List<TaskDtos.InstanceResponse> skipped = all.stream().filter(i -> "SKIPPED".equals(i.status())).toList();
        List<TaskDtos.InstanceResponse> pending = all.stream().filter(i -> "PENDING".equals(i.status())).toList();
        List<TaskDtos.InstanceResponse> timeline = pending.stream().filter(i -> !i.allDay())
                .sorted(Comparator.comparing(TaskDtos.InstanceResponse::currentDueAt)).toList();
        List<TaskDtos.InstanceResponse> allDay = pending.stream().filter(TaskDtos.InstanceResponse::allDay)
                .sorted(Comparator.comparing(TaskDtos.InstanceResponse::title)).toList();
        int overdue = (int) pending.stream().filter(TaskDtos.InstanceResponse::overdue).count();
        var summary = new TaskDtos.DaySummary(all.size(), completed.size(), pending.size(), skipped.size(), overdue);
        return new TaskDtos.DayResponse(date, all.isEmpty() ? "EMPTY" : "READY", timeline, allDay, completed,
                skipped, summary, !"COMPLETE_PROFILE".equals(healthGuide) && healthLinks.hasPlanUpdate(userId), healthGuide);
    }

    @Transactional
    public TaskDtos.InstanceResponse complete(String userId, String id, String operationKey, String timezone) {
        return operate(userId, id, operationKey, "COMPLETE", null, timezone);
    }

    @Transactional
    public TaskDtos.InstanceResponse reopen(String userId, String id, String operationKey, String timezone) {
        return operate(userId, id, operationKey, "REOPEN", null, timezone);
    }

    @Transactional
    public TaskDtos.InstanceResponse skip(String userId, String id, String operationKey, String reason,
                                           String timezone) {
        if (reason != null && reason.trim().length() > 200) throw invalid("skipReason", "跳过原因最多 200 个字符");
        return operate(userId, id, operationKey, "SKIP", reason == null ? null : reason.trim(), timezone);
    }

    @Transactional
    public TaskDtos.InstanceResponse postpone(String userId, String id, String operationKey,
                                               TaskDtos.PostponeRequest request) {
        String key = key(operationKey);
        TaskDtos.InstanceResponse replay = replay(userId, key, "POSTPONE");
        if (replay != null) return replay;
        TaskDtos.InstanceResponse current = requireInstance(userId, id);
        if (!"PENDING".equals(current.status())) throw conflict("TASK_STATE_CONFLICT", "只有待完成任务可以延期");
        if (request == null || request.type() == null) throw invalid("type", "请选择延期方式");
        ZoneId zone = schedule.zone(request.timezone());
        String type = request.type().trim().toUpperCase(Locale.ROOT);
        LocalDate date;
        Instant due;
        if ("LATER".equals(type)) {
            if (current.currentDueAt() == null) throw invalid("type", "全天任务不能稍后 30 分钟");
            due = current.currentDueAt().plusSeconds(1800);
            date = due.atZone(zone).toLocalDate();
        } else if ("TOMORROW".equals(type)) {
            date = current.currentLocalDate().plusDays(1);
            due = current.allDay() ? null : schedule.toInstant(date, LocalTime.parse(current.localTime()), zone.getId());
        } else if ("CUSTOM".equals(type)) {
            if (request.customAt() == null) throw invalid("customAt", "请选择延期时间");
            due = request.customAt().toInstant();
            if (!due.isAfter(clock.instant())) throw invalid("customAt", "延期时间必须晚于当前时间");
            date = due.atZone(zone).toLocalDate();
        } else {
            throw invalid("type", "延期方式不正确");
        }
        TaskDtos.InstanceResponse concurrentReplay = reserve(userId, key, id, "POSTPONE");
        if (concurrentReplay != null) return concurrentReplay;
        jdbc.update("UPDATE task_instances SET current_local_date=?,current_due_at=?,timezone=?,"
                        + "postponed_from=COALESCE(postponed_from,current_due_at),postpone_count=postpone_count+1,"
                        + "version=version+1,updated_at=? WHERE id=? AND user_id=? AND deleted_at IS NULL",
                date, timestamp(due), zone.getId(), now(), id, userId);
        return requireInstance(userId, id);
    }

    @Transactional
    public TaskDtos.InstanceResponse updateInstance(String userId, String id,
                                                     TaskDtos.InstanceUpdateRequest request) {
        TaskDtos.InstanceResponse current = requireInstance(userId, id);
        if (request == null || request.expectedVersion() == null)
            throw invalid("expectedVersion", "请提供任务版本");
        Values values = validate(new TaskDtos.CreateRequest(request.title(), request.note(), request.category(),
                request.priority(), request.allDay(), request.localTime(), current.currentLocalDate(), "NONE", null,
                request.reminderOffsetMinutes(), request.timezone()));
        Instant due = values.allDay() ? null : schedule.toInstant(current.currentLocalDate(), values.time(),
                values.zone().getId());
        int changed = jdbc.update("""
                UPDATE task_instances SET title=?,note=?,category=?,priority=?,all_day=?,local_time=?,
                reminder_offset_minutes=?,current_due_at=?,timezone=?,version=version+1,updated_at=?
                WHERE id=? AND user_id=? AND deleted_at IS NULL AND version=?
                """, values.title(), values.note(), values.category(), values.priority(), values.allDay(),
                time(values.time()), values.reminder(), timestamp(due), values.zone().getId(), now(), id, userId,
                request.expectedVersion());
        if (changed == 0) throw conflict("TASK_VERSION_CONFLICT", "任务已在其他设备更新，请刷新后重试");
        return requireInstance(userId, id);
    }

    @Transactional
    public TaskDtos.CreateResponse updateTemplate(String userId, String id,
                                                   TaskDtos.TemplateUpdateRequest request) {
        requireTemplate(userId, id);
        if (request == null || request.expectedVersion() == null)
            throw invalid("expectedVersion", "请提供任务版本");
        Values values = validate(new TaskDtos.CreateRequest(request.title(), request.note(), request.category(),
                request.priority(), request.allDay(), request.localTime(), request.effectiveDate(),
                request.recurrenceType(), request.weekdaysMask(), request.reminderOffsetMinutes(), request.timezone()));
        int changed = jdbc.update("""
                UPDATE task_templates SET title=?,note=?,category=?,priority=?,all_day=?,local_time=?,recurrence_type=?,
                weekdays_mask=?,reminder_offset_minutes=?,user_overridden=TRUE,version=version+1,updated_at=?
                WHERE id=? AND user_id=? AND version=?
                """, values.title(), values.note(), values.category(), values.priority(), values.allDay(),
                time(values.time()), values.recurrence(), values.weekdaysMask(), values.reminder(), now(), id, userId,
                request.expectedVersion());
        if (changed == 0) throw conflict("TASK_VERSION_CONFLICT", "任务安排已在其他设备更新，请刷新后重试");
        List<String> instanceIds = jdbc.query("SELECT id FROM task_instances WHERE template_id=? AND user_id=? "
                        + "AND original_local_date>=? AND status='PENDING' AND postpone_count=0 AND deleted_at IS NULL",
                (rs, row) -> rs.getString(1), id, userId, values.date());
        for (String instanceId : instanceIds) {
            TaskDtos.InstanceResponse instance = requireInstance(userId, instanceId);
            Instant originalDue = values.allDay() ? null : schedule.toInstant(instance.originalLocalDate(),
                    values.time(), values.zone().getId());
            jdbc.update("""
                    UPDATE task_instances SET title=?,note=?,category=?,priority=?,all_day=?,local_time=?,
                    reminder_offset_minutes=?,original_due_at=?,current_due_at=?,timezone=?,version=version+1,updated_at=?
                    WHERE id=?
                    """, values.title(), values.note(), values.category(), values.priority(), values.allDay(),
                    time(values.time()), values.reminder(), timestamp(originalDue), timestamp(originalDue),
                    values.zone().getId(), now(), instanceId);
        }
        return createResponse(userId, id);
    }

    @Transactional
    public void deleteInstance(String userId, String id, String timezone) {
        schedule.zone(timezone);
        requireInstance(userId, id);
        jdbc.update("UPDATE task_instances SET deleted_at=?,version=version+1,updated_at=? "
                + "WHERE id=? AND user_id=? AND deleted_at IS NULL", now(), now(), id, userId);
    }

    @Transactional
    public void deleteTemplate(String userId, String id, LocalDate effectiveDate, String timezone) {
        schedule.zone(timezone);
        requireTemplate(userId, id);
        if (effectiveDate == null) throw invalid("effectiveDate", "请选择停止日期");
        jdbc.update("UPDATE task_templates SET disabled_from=?,user_overridden=TRUE,version=version+1,updated_at=? "
                + "WHERE id=? AND user_id=?", effectiveDate, now(), id, userId);
        jdbc.update("UPDATE task_instances SET deleted_at=?,version=version+1,updated_at=? WHERE template_id=? "
                        + "AND user_id=? AND original_local_date>=? AND status='PENDING' AND postpone_count=0 "
                        + "AND deleted_at IS NULL", now(), now(), id, userId, effectiveDate);
    }

    @Transactional
    public TaskDtos.SettingsResponse settings(String userId) {
        jdbc.update("MERGE INTO task_settings (user_id) KEY(user_id) VALUES (?)", userId);
        return jdbc.queryForObject("SELECT * FROM task_settings WHERE user_id=?", (rs, row) -> settings(rs), userId);
    }

    @Transactional
    public TaskDtos.SettingsResponse updateSettings(String userId, TaskDtos.SettingsRequest request) {
        settings(userId);
        if (request == null || request.quietEnabled() == null) throw invalid("quietEnabled", "请选择勿扰状态");
        if (request.expectedVersion() == null) throw invalid("expectedVersion", "请提供设置版本");
        LocalTime start = parseTime(request.quietStartTime(), "quietStartTime");
        LocalTime end = parseTime(request.quietEndTime(), "quietEndTime");
        if (start.equals(end)) throw invalid("quietEndTime", "勿扰开始和结束时间不能相同");
        int changed = jdbc.update("UPDATE task_settings SET quiet_enabled=?,quiet_start_time=?,quiet_end_time=?,"
                        + "version=version+1,updated_at=? WHERE user_id=? AND version=?", request.quietEnabled(),
                Time.valueOf(start), Time.valueOf(end), now(), userId, request.expectedVersion());
        if (changed == 0) throw conflict("TASK_VERSION_CONFLICT", "设置已在其他设备更新，请刷新后重试");
        return settings(userId);
    }

    @Transactional
    public List<TaskDtos.NotificationResponse> notifications(String userId, LocalDate from, LocalDate to,
                                                              String timezone) {
        ZoneId zone = schedule.zone(timezone);
        LocalDate today = today(zone);
        if (from == null || to == null || from.isAfter(to)) throw invalid("from", "通知日期范围不正确");
        if (from.isBefore(today) || to.isAfter(today.plusDays(7)))
            throw invalid("to", "通知最多查询未来 7 天");
        for (LocalDate date = from; !date.isAfter(to); date = date.plusDays(1)) {
            healthLinks.ensurePlanTemplates(userId, date, zone.getId());
            ensureInstances(userId, date, zone);
            healthLinks.reconcile(userId, date, zone.getId());
        }
        TaskDtos.SettingsResponse settings = settings(userId);
        List<TaskDtos.InstanceResponse> values = instances(userId,
                "i.current_local_date BETWEEN ? AND ? AND i.status='PENDING' AND i.deleted_at IS NULL "
                        + "AND i.current_due_at IS NOT NULL AND i.reminder_offset_minutes IS NOT NULL", from, to);
        if ("COMPLETE_PROFILE".equals(healthLinks.healthGuide(userId))) {
            values = values.stream().filter(i -> "USER".equals(i.source())).toList();
        }
        List<TaskDtos.NotificationResponse> result = new ArrayList<>();
        for (TaskDtos.InstanceResponse value : values) {
            Instant notifyAt = value.currentDueAt().minusSeconds(value.reminderOffsetMinutes() * 60L);
            if (notifyAt.isBefore(clock.instant()) || quiet(notifyAt.atZone(zone).toLocalTime(), settings)) continue;
            result.add(new TaskDtos.NotificationResponse(value.id(), value.title(), value.currentDueAt(), notifyAt,
                    value.timezone(), value.category(), value.source()));
        }
        result.sort(Comparator.comparing(TaskDtos.NotificationResponse::notifyAt));
        return result;
    }

    @Transactional
    public TaskDtos.NotificationEventsResponse notificationEvents(String userId,
                                                                   TaskDtos.NotificationEventsRequest request) {
        if (request == null || request.events() == null || request.events().isEmpty())
            throw invalid("events", "请提供通知事件");
        int accepted = 0;
        for (TaskDtos.NotificationEventRequest event : request.events()) {
            if (event == null || !Set.of("SCHEDULED", "CANCELLED", "OPENED").contains(event.eventType()))
                throw invalid("eventType", "通知事件类型不正确");
            if (event.deviceKeyHash() == null || !event.deviceKeyHash().matches("[0-9a-fA-F]{64}"))
                throw invalid("deviceKeyHash", "设备标识必须使用不可逆摘要");
            String eventKey = key(event.idempotencyKey());
            if (event.instanceId() != null) requireInstance(userId, event.instanceId());
            try {
                accepted += jdbc.update("""
                        INSERT INTO task_notification_events
                        (id,user_id,task_instance_id,device_key_hash,event_type,scheduled_for,occurred_at,idempotency_key)
                        VALUES (?,?,?,?,?,?,?,?)
                        """, UUID.randomUUID().toString(), userId, event.instanceId(), event.deviceKeyHash(),
                        event.eventType(), timestamp(event.scheduledFor()),
                        timestamp(event.occurredAt() == null ? clock.instant() : event.occurredAt()), eventKey);
            } catch (DataIntegrityViolationException ignored) {
                // Same user/key is an accepted retry.
            }
        }
        return new TaskDtos.NotificationEventsResponse(accepted);
    }

    public TaskDtos.WeekResponse week(String userId, LocalDate date, String timezone) {
        schedule.zone(timezone);
        if (date == null) throw invalid("date", "请选择日期");
        LocalDate start = date.minusDays(6);
        List<TaskDtos.InstanceResponse> values = instances(userId,
                "i.original_local_date BETWEEN ? AND ? AND i.deleted_at IS NULL", start, date);
        if ("COMPLETE_PROFILE".equals(healthLinks.healthGuide(userId))) {
            values = values.stream().filter(i -> "USER".equals(i.source())).toList();
        }
        int completed = (int) values.stream().filter(i -> "COMPLETED".equals(i.status())).count();
        int skipped = (int) values.stream().filter(i -> "SKIPPED".equals(i.status())).count();
        int postponed = (int) values.stream().filter(i -> i.postponeCount() > 0).count();
        int overdue = (int) values.stream().filter(TaskDtos.InstanceResponse::overdue).count();
        int userCompleted = (int) values.stream().filter(i -> "USER".equals(i.completionSource())).count();
        int autoCompleted = (int) values.stream().filter(i -> "AUTO_HEALTH_DATA".equals(i.completionSource())).count();
        BigDecimal rate = values.isEmpty() ? null : BigDecimal.valueOf(completed)
                .divide(BigDecimal.valueOf(values.size()), 4, RoundingMode.HALF_UP);
        List<TaskDtos.InstanceResponse> visibleValues = values;
        List<TaskDtos.CategorySummary> categories = CATEGORY_ORDER.stream().map(category -> {
            List<TaskDtos.InstanceResponse> categoryValues = visibleValues.stream()
                    .filter(i -> category.equals(i.category())).toList();
            return new TaskDtos.CategorySummary(category, categoryValues.size(),
                    (int) categoryValues.stream().filter(i -> "COMPLETED".equals(i.status())).count());
        }).toList();
        return new TaskDtos.WeekResponse(start, date, values.size(), completed, skipped, postponed, overdue, rate,
                userCompleted, autoCompleted, categories);
    }

    public TaskDtos.TodaySummary todaySummary(String userId, LocalDate date, String timezone) {
        TaskDtos.DayResponse day = day(userId, date, timezone);
        List<TaskDtos.InstanceResponse> pending = new ArrayList<>();
        pending.addAll(day.timeline());
        pending.addAll(day.allDay());
        TaskDtos.InstanceResponse next = pending.isEmpty() ? null : pending.get(0);
        TaskDtos.NextTask nextTask = next == null ? null : new TaskDtos.NextTask(next.id(), next.title(),
                next.currentDueAt(), next.currentLocalDate(), next.category(), next.source(), next.allDay());
        TaskDtos.DaySummary summary = day.summary();
        return new TaskDtos.TodaySummary(day.status(), summary.totalCount(), summary.completedCount(),
                summary.pendingCount(), summary.overdueCount(), nextTask, day.hasPlanUpdate(), day.healthGuide());
    }

    @Transactional
    public void adoptPlanUpdates(String userId, LocalDate date, String timezone) {
        schedule.zone(timezone);
        healthLinks.adoptPlanUpdates(userId, date, timezone);
    }

    private TaskDtos.InstanceResponse operate(String userId, String id, String operationKey, String operation,
                                               String reason, String timezone) {
        schedule.zone(timezone);
        String key = key(operationKey);
        TaskDtos.InstanceResponse replay = replay(userId, key, operation);
        if (replay != null) return replay;
        requireInstance(userId, id);
        TaskDtos.InstanceResponse concurrentReplay = reserve(userId, key, id, operation);
        if (concurrentReplay != null) return concurrentReplay;
        if ("COMPLETE".equals(operation)) {
            jdbc.update("UPDATE task_instances SET status='COMPLETED',completion_source='USER',completed_at=?,"
                    + "skipped_at=NULL,skip_reason=NULL,version=version+1,updated_at=? WHERE id=? AND user_id=?",
                    now(), now(), id, userId);
        } else if ("SKIP".equals(operation)) {
            jdbc.update("UPDATE task_instances SET status='SKIPPED',completion_source=NULL,completed_at=NULL,"
                    + "skipped_at=?,skip_reason=?,version=version+1,updated_at=? WHERE id=? AND user_id=?",
                    now(), reason, now(), id, userId);
        } else {
            jdbc.update("UPDATE task_instances SET status='PENDING',completion_source=NULL,completed_at=NULL,"
                    + "skipped_at=NULL,skip_reason=NULL,version=version+1,updated_at=? WHERE id=? AND user_id=?",
                    now(), id, userId);
        }
        return requireInstance(userId, id);
    }

    private TaskDtos.InstanceResponse replay(String userId, String key, String operation) {
        List<String[]> rows = jdbc.query("SELECT instance_id,operation_type FROM task_operation_keys "
                        + "WHERE user_id=? AND idempotency_key=?",
                (rs, row) -> new String[]{rs.getString(1), rs.getString(2)}, userId, key);
        if (rows.isEmpty()) return null;
        if (!operation.equals(rows.get(0)[1])) throw conflict("IDEMPOTENCY_KEY_REUSED", "幂等键已用于其他操作");
        return requireInstance(userId, rows.get(0)[0]);
    }

    private TaskDtos.InstanceResponse reserve(String userId, String key, String id, String operation) {
        try {
            jdbc.update("INSERT INTO task_operation_keys (user_id,idempotency_key,instance_id,operation_type) "
                    + "VALUES (?,?,?,?)", userId, key, id, operation);
            return null;
        } catch (DataIntegrityViolationException exception) {
            TaskDtos.InstanceResponse replay = replay(userId, key, operation);
            if (replay != null) return replay;
            throw exception;
        }
    }

    private void ensureInstances(String userId, LocalDate date, ZoneId zone) {
        List<String[]> templates = jdbc.query("""
                SELECT id,source FROM task_templates WHERE user_id=? AND effective_from<=?
                AND (disabled_from IS NULL OR disabled_from>?)
                """, (rs, row) -> new String[]{rs.getString(1), rs.getString(2)}, userId, date, date);
        boolean planEnabled = healthLinks.planTasksEnabled(userId);
        for (String[] template : templates) {
            if ("USER".equals(template[1]) || planEnabled) generate(template[0], userId, date, zone);
        }
    }

    private void generate(String templateId, String userId, LocalDate date, ZoneId zone) {
        List<Template> templates = jdbc.query("SELECT * FROM task_templates WHERE id=? AND user_id=?",
                (rs, row) -> template(rs), templateId, userId);
        if (templates.isEmpty()) return;
        Template template = templates.get(0);
        if (date.isBefore(template.effectiveFrom())
                || template.disabledFrom() != null && !date.isBefore(template.disabledFrom())
                || !schedule.matches(template.recurrence(), template.weekdaysMask(), date, template.effectiveFrom()))
            return;
        Instant due = template.allDay() ? null : schedule.toInstant(date, template.time(), zone.getId());
        try {
            jdbc.update("""
                    INSERT INTO task_instances
                    (id,user_id,template_id,original_local_date,current_local_date,original_due_at,current_due_at,
                     timezone,status,title,note,category,priority,all_day,local_time,reminder_offset_minutes,
                     postpone_count,version,created_at,updated_at)
                    VALUES (?,?,?,?,?,?,?,?,'PENDING',?,?,?,?,?,?,?,?,0,?,?)
                    """, UUID.randomUUID().toString(), userId, template.id(), date, date, timestamp(due),
                    timestamp(due), zone.getId(), template.title(), template.note(), template.category(),
                    template.priority(), template.allDay(), time(template.time()), template.reminder(), 0,
                    now(), now());
        } catch (DataIntegrityViolationException ignored) {
            // Unique(template,date) makes read-time generation concurrency safe.
        }
    }

    private Values validate(TaskDtos.CreateRequest request) {
        if (request == null) throw invalid("task", "请填写任务");
        String title = request.title() == null ? "" : request.title().trim();
        if (title.isEmpty() || title.length() > 80) throw invalid("title", "任务名称须为 1–80 个字符");
        String note = request.note() == null ? null : request.note().trim();
        if (note != null && note.isEmpty()) note = null;
        if (note != null && note.length() > 500) throw invalid("note", "备注最多 500 个字符");
        String category = upper(request.category());
        if (!CATEGORIES.contains(category)) throw invalid("category", "任务分类不正确");
        String priority = upper(request.priority());
        if (!PRIORITIES.contains(priority)) throw invalid("priority", "任务优先级不正确");
        if (request.allDay() == null) throw invalid("allDay", "请选择是否为全天任务");
        LocalTime localTime = request.allDay() ? null : parseTime(request.localTime(), "localTime");
        if (request.allDay() && request.localTime() != null && !request.localTime().isBlank())
            throw invalid("localTime", "全天任务不能设置时间");
        if (request.reminderOffsetMinutes() != null && !REMINDERS.contains(request.reminderOffsetMinutes()))
            throw invalid("reminderOffsetMinutes", "提醒时间不正确");
        if (request.allDay() && request.reminderOffsetMinutes() != null)
            throw invalid("reminderOffsetMinutes", "全天任务设置提醒前须先选择时间");
        String recurrence = upper(request.recurrenceType());
        schedule.validateRule(recurrence, request.weekdaysMask(), request.date());
        ZoneId zone = schedule.zone(request.timezone());
        if (!request.allDay()) schedule.toInstant(request.date(), localTime, zone.getId());
        return new Values(title, note, category, priority, request.allDay(), localTime, request.date(), recurrence,
                request.weekdaysMask(), request.reminderOffsetMinutes(), zone);
    }

    private List<TaskDtos.InstanceResponse> instances(String userId, String condition, Object... args) {
        Object[] parameters = new Object[args.length + 1];
        parameters[0] = userId;
        System.arraycopy(args, 0, parameters, 1, args.length);
        return jdbc.query("SELECT i.*,t.source,t.plan_version,t.user_overridden FROM task_instances i "
                        + "JOIN task_templates t ON t.id=i.template_id WHERE i.user_id=? AND " + condition
                        + " ORDER BY i.current_due_at,i.title,i.id",
                (rs, row) -> instance(rs), parameters);
    }

    private TaskDtos.InstanceResponse requireInstance(String userId, String id) {
        List<TaskDtos.InstanceResponse> values = instances(userId, "i.id=? AND i.deleted_at IS NULL", id);
        if (values.isEmpty()) throw notFound();
        return values.get(0);
    }

    private void requireTemplate(String userId, String id) {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM task_templates WHERE id=? AND user_id=?",
                Integer.class, id, userId);
        if (count == null || count == 0) throw notFound();
    }

    private TaskDtos.CreateResponse createResponse(String userId, String templateId) {
        Integer version = jdbc.queryForObject("SELECT version FROM task_templates WHERE id=? AND user_id=?",
                Integer.class, templateId, userId);
        if (version == null) throw notFound();
        return new TaskDtos.CreateResponse(templateId, version,
                instances(userId, "i.template_id=? AND i.deleted_at IS NULL", templateId));
    }

    private TaskDtos.InstanceResponse instance(ResultSet rs) throws SQLException {
        Timestamp due = rs.getTimestamp("current_due_at");
        Timestamp originalDue = rs.getTimestamp("original_due_at");
        Timestamp completed = rs.getTimestamp("completed_at");
        Timestamp skipped = rs.getTimestamp("skipped_at");
        LocalTime localTime = rs.getTime("local_time") == null ? null : rs.getTime("local_time").toLocalTime();
        boolean overdue = "PENDING".equals(rs.getString("status")) && due != null
                && due.toInstant().isBefore(clock.instant());
        return new TaskDtos.InstanceResponse(rs.getString("id"), rs.getString("template_id"),
                rs.getString("source"), rs.getString("title"), rs.getString("note"), rs.getString("category"),
                rs.getString("priority"), rs.getBoolean("all_day"), localTime == null ? null : localTime.toString(),
                (Integer) rs.getObject("reminder_offset_minutes"), rs.getObject("original_local_date", LocalDate.class),
                rs.getObject("current_local_date", LocalDate.class), originalDue == null ? null : originalDue.toInstant(),
                due == null ? null : due.toInstant(), rs.getString("timezone"), rs.getString("status"),
                rs.getString("completion_source"), completed == null ? null : completed.toInstant(),
                skipped == null ? null : skipped.toInstant(), rs.getString("skip_reason"),
                rs.getInt("postpone_count"), overdue, false, rs.getInt("version"));
    }

    private Template template(ResultSet rs) throws SQLException {
        Time value = rs.getTime("local_time");
        return new Template(rs.getString("id"), rs.getString("title"), rs.getString("note"),
                rs.getString("category"), rs.getString("priority"), rs.getBoolean("all_day"),
                value == null ? null : value.toLocalTime(), rs.getString("recurrence_type"),
                (Integer) rs.getObject("weekdays_mask"), (Integer) rs.getObject("reminder_offset_minutes"),
                rs.getObject("effective_from", LocalDate.class), rs.getObject("disabled_from", LocalDate.class));
    }

    private TaskDtos.SettingsResponse settings(ResultSet rs) throws SQLException {
        return new TaskDtos.SettingsResponse(rs.getBoolean("quiet_enabled"),
                rs.getTime("quiet_start_time").toLocalTime().toString(),
                rs.getTime("quiet_end_time").toLocalTime().toString(), rs.getInt("version"));
    }

    private boolean quiet(LocalTime time, TaskDtos.SettingsResponse settings) {
        if (!settings.quietEnabled()) return false;
        LocalTime start = LocalTime.parse(settings.quietStartTime());
        LocalTime end = LocalTime.parse(settings.quietEndTime());
        return start.isBefore(end) ? !time.isBefore(start) && time.isBefore(end)
                : !time.isBefore(start) || time.isBefore(end);
    }

    private String key(String value) {
        if (value == null || value.isBlank()) throw invalid("Idempotency-Key", "操作需要 Idempotency-Key");
        if (value.trim().length() > 100) throw invalid("Idempotency-Key", "Idempotency-Key 最多 100 个字符");
        return value.trim();
    }

    private LocalTime parseTime(String value, String field) {
        if (value == null || value.isBlank()) throw invalid(field, "请选择时间");
        try {
            return LocalTime.parse(value.trim());
        } catch (DateTimeParseException exception) {
            throw invalid(field, "时间格式不正确");
        }
    }

    private LocalDate today(ZoneId zone) {
        return LocalDate.now(clock.withZone(zone));
    }

    private String upper(String value) {
        return value == null ? "" : value.trim().toUpperCase(Locale.ROOT);
    }

    private Time time(LocalTime value) {
        return value == null ? null : Time.valueOf(value);
    }

    private Timestamp timestamp(Instant value) {
        return value == null ? null : Timestamp.from(value);
    }

    private Timestamp now() {
        return Timestamp.from(clock.instant());
    }

    private ApiException invalid(String field, String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, "INVALID_TASK", message,
                List.of(new ApiFieldError(field, message)));
    }

    private ApiException conflict(String code, String message) {
        return new ApiException(HttpStatus.CONFLICT, code, message);
    }

    private ApiException notFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "TASK_NOT_FOUND", "任务不存在");
    }

    private record Values(String title, String note, String category, String priority, boolean allDay,
                          LocalTime time, LocalDate date, String recurrence, Integer weekdaysMask,
                          Integer reminder, ZoneId zone) {
    }

    private record Template(String id, String title, String note, String category, String priority,
                            boolean allDay, LocalTime time, String recurrence, Integer weekdaysMask,
                            Integer reminder, LocalDate effectiveFrom, LocalDate disabledFrom) {
    }
}
