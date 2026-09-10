package com.lightbite.healthy.tasks;

import com.lightbite.healthy.activity.ActivityService;
import com.lightbite.healthy.hydration.HydrationService;
import com.lightbite.healthy.nutrition.NutritionService;
import com.lightbite.healthy.plan.PlanDtos;
import com.lightbite.healthy.plan.PlanService;
import com.lightbite.healthy.sleep.SleepService;
import java.sql.Time;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class TaskHealthLinkService {
    private final JdbcTemplate jdbc;
    private final TaskSchedulePolicy schedule;
    private final PlanService plans;
    private final NutritionService nutrition;
    private final HydrationService hydration;
    private final ActivityService activity;
    private final SleepService sleep;

    public TaskHealthLinkService(JdbcTemplate jdbc, TaskSchedulePolicy schedule, PlanService plans,
                                 NutritionService nutrition, HydrationService hydration,
                                 ActivityService activity, SleepService sleep) {
        this.jdbc = jdbc;
        this.schedule = schedule;
        this.plans = plans;
        this.nutrition = nutrition;
        this.hydration = hydration;
        this.activity = activity;
        this.sleep = sleep;
    }

    @Transactional
    public void ensurePlanTemplates(String userId, LocalDate date, String timezone) {
        schedule.zone(timezone);
        PlanDtos.CurrentResponse current = plans.current(userId);
        if (!active(current)) return;
        for (DefaultTask task : defaults(current)) {
            Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM task_templates "
                    + "WHERE user_id=? AND source='PLAN' AND plan_id=? AND task_code=?", Integer.class,
                    userId, current.planId(), task.code());
            if (count != null && count > 0) continue;
            jdbc.update("""
                    INSERT INTO task_templates
                    (id,user_id,source,plan_id,plan_version,task_code,title,category,priority,all_day,local_time,
                     recurrence_type,weekdays_mask,health_link_type,health_link_target,effective_from,
                     user_overridden,version,created_at,updated_at)
                    VALUES (?,?,'PLAN',?,?,?,?,'HEALTH','NORMAL',FALSE,?,?,?,?,?,?,FALSE,0,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)
                    """, UUID.randomUUID().toString(), userId, current.planId(), current.currentVersion(), task.code(),
                    task.title(), Time.valueOf(task.time()), task.recurrence(), task.weekdaysMask(), task.linkType(),
                    task.target(), date);
        }
    }

    public boolean planTasksEnabled(String userId) {
        return active(plans.current(userId));
    }

    @Transactional
    public void reconcile(String userId, LocalDate date, String timezone) {
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT i.id,i.status,i.completion_source,i.postpone_count,t.health_link_type,t.health_link_target
                FROM task_instances i JOIN task_templates t ON t.id=i.template_id
                WHERE i.user_id=? AND i.current_local_date=? AND i.deleted_at IS NULL AND t.source='PLAN'
                """, userId, date);
        Map<String, Boolean> results = new HashMap<>();
        for (Map<String, Object> row : rows) {
            String type = (String) row.get("health_link_type");
            Integer target = (Integer) row.get("health_link_target");
            boolean satisfied = results.computeIfAbsent(type + ":" + target,
                    ignored -> satisfied(userId, date, timezone, type, target));
            String status = (String) row.get("status");
            String source = (String) row.get("completion_source");
            int postponed = ((Number) row.get("postpone_count")).intValue();
            String id = (String) row.get("id");
            if (satisfied && "PENDING".equals(status) && postponed == 0) {
                jdbc.update("UPDATE task_instances SET status='COMPLETED',completion_source='AUTO_HEALTH_DATA',"
                        + "completed_at=CURRENT_TIMESTAMP,version=version+1,updated_at=CURRENT_TIMESTAMP WHERE id=?", id);
            } else if (!satisfied && "COMPLETED".equals(status) && "AUTO_HEALTH_DATA".equals(source)) {
                jdbc.update("UPDATE task_instances SET status='PENDING',completion_source=NULL,completed_at=NULL,"
                        + "version=version+1,updated_at=CURRENT_TIMESTAMP WHERE id=?", id);
            }
        }
    }

    public boolean hasPlanUpdate(String userId) {
        PlanDtos.CurrentResponse current = plans.current(userId);
        if (current == null || current.planId() == null || current.currentVersion() == null) return false;
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM task_templates WHERE user_id=? AND source='PLAN' "
                + "AND plan_id=? AND plan_version<>?", Integer.class, userId, current.planId(), current.currentVersion());
        return count != null && count > 0;
    }

    public String healthGuide(String userId) {
        Integer complete = jdbc.queryForObject("SELECT COUNT(*) FROM health_profiles WHERE user_id=? AND completed=TRUE",
                Integer.class, userId);
        if (complete == null || complete == 0) return "COMPLETE_PROFILE";
        PlanDtos.CurrentResponse current = plans.current(userId);
        if (current == null || "EMPTY".equals(current.state())) return "CREATE_PLAN";
        return switch (current.state()) {
            case "PAUSED" -> "RESUME_PLAN";
            case "NEEDS_RECALCULATION" -> "RECALCULATE_PLAN";
            case "RISK_BLOCKED" -> "VIEW_RISK_GUIDANCE";
            default -> null;
        };
    }

    @Transactional
    public void adoptPlanUpdates(String userId, LocalDate date, String timezone) {
        PlanDtos.CurrentResponse current = plans.current(userId);
        if (!active(current)) return;
        Map<String, DefaultTask> defaults = new HashMap<>();
        for (DefaultTask task : defaults(current)) defaults.put(task.code(), task);
        List<Map<String, Object>> templates = jdbc.queryForList("SELECT id,task_code FROM task_templates "
                + "WHERE user_id=? AND source='PLAN' AND plan_id=?", userId, current.planId());
        for (Map<String, Object> row : templates) {
            DefaultTask task = defaults.get((String) row.get("task_code"));
            if (task == null) continue;
            String templateId = (String) row.get("id");
            jdbc.update("""
                    UPDATE task_templates SET plan_version=?,title=?,local_time=?,recurrence_type=?,weekdays_mask=?,
                    health_link_target=?,disabled_from=NULL,user_overridden=FALSE,version=version+1,
                    updated_at=CURRENT_TIMESTAMP WHERE id=?
                    """, current.currentVersion(), task.title(), Time.valueOf(task.time()), task.recurrence(),
                    task.weekdaysMask(), task.target(), templateId);
            List<Map<String, Object>> instances = jdbc.queryForList("SELECT id,original_local_date FROM task_instances "
                    + "WHERE template_id=? AND original_local_date>=? AND status='PENDING' AND postpone_count=0 "
                    + "AND deleted_at IS NULL", templateId, date);
            for (Map<String, Object> instance : instances) {
                LocalDate instanceDate = localDate(instance.get("original_local_date"));
                Instant due = schedule.toInstant(instanceDate, task.time(), timezone);
                jdbc.update("UPDATE task_instances SET title=?,local_time=?,original_due_at=?,current_due_at=?,"
                                + "timezone=?,version=version+1,updated_at=CURRENT_TIMESTAMP WHERE id=?",
                        task.title(), Time.valueOf(task.time()), Timestamp.from(due), Timestamp.from(due), timezone,
                        instance.get("id"));
            }
        }
        ensurePlanTemplates(userId, date, timezone);
    }

    private boolean satisfied(String userId, LocalDate date, String timezone, String type, Integer target) {
        if (type == null) return false;
        if (type.startsWith("MEAL_")) {
            String mealType = type.substring("MEAL_".length());
            return nutrition.day(userId, date).meals().stream()
                    .anyMatch(meal -> mealType.equals(meal.mealType()) && !meal.entries().isEmpty());
        }
        return switch (type) {
            case "HYDRATION_TARGET" -> {
                var day = hydration.day(userId, date, timezone);
                yield day.targetMl() > 0 && day.totalMl() >= day.targetMl();
            }
            case "ACTIVITY_SESSION" -> activity.day(userId, date, timezone).totalDurationMinutes() >= target;
            case "SLEEP_RECORD" -> sleep.day(userId, date, timezone).night() != null;
            default -> false;
        };
    }

    private List<DefaultTask> defaults(PlanDtos.CurrentResponse current) {
        List<DefaultTask> values = new ArrayList<>();
        values.add(new DefaultTask("MEAL_BREAKFAST", "记录早餐", LocalTime.of(8, 0), "DAILY", null,
                "MEAL_BREAKFAST", null));
        values.add(new DefaultTask("MEAL_LUNCH", "记录午餐", LocalTime.of(12, 0), "DAILY", null,
                "MEAL_LUNCH", null));
        values.add(new DefaultTask("MEAL_DINNER", "记录晚餐", LocalTime.of(18, 0), "DAILY", null,
                "MEAL_DINNER", null));
        values.add(new DefaultTask("HYDRATION_TARGET", "完成今日饮水", LocalTime.of(20, 0), "DAILY", null,
                "HYDRATION_TARGET", null));
        values.add(new DefaultTask("SLEEP_RECORD", "记录昨晚睡眠", LocalTime.of(8, 0), "DAILY", null,
                "SLEEP_RECORD", null));
        int days = current.plan().exerciseDays();
        int totalMinutes = current.plan().exerciseMinutes();
        int base = totalMinutes / days;
        int remainder = totalMinutes % days;
        for (int i = 0; i < days; i++) {
            int weekday = i * 7 / days;
            int minutes = base + (i < remainder ? 1 : 0);
            values.add(new DefaultTask("ACTIVITY_SESSION_" + (i + 1), "完成运动 " + minutes + " 分钟",
                    LocalTime.of(18, 30), "WEEKLY_DAYS", 1 << weekday, "ACTIVITY_SESSION", minutes));
        }
        return values;
    }

    private boolean active(PlanDtos.CurrentResponse current) {
        return current != null && "ACTIVE".equals(current.state()) && current.planId() != null
                && current.currentVersion() != null && current.plan() != null;
    }

    private LocalDate localDate(Object value) {
        return value instanceof LocalDate local ? local : ((java.sql.Date) value).toLocalDate();
    }

    private record DefaultTask(String code, String title, LocalTime time, String recurrence,
                               Integer weekdaysMask, String linkType, Integer target) {
    }
}
