package com.lightbite.healthy.report;

import java.math.BigDecimal;
import java.sql.Date;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

@Component
public class ReportDataCollector {
    private final JdbcTemplate jdbc;

    public ReportDataCollector(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public ReportDtos.Facts collect(String userId, ReportDtos.Period period) {
        Map<String, Object> targets = new LinkedHashMap<>();
        Map<String, Object> metrics = new LinkedHashMap<>();
        List<ReportDtos.Source> sources = new ArrayList<>();
        Plan plan = plan(userId, period);
        if (plan != null) {
            targets.put("calories", plan.targetKcal);
            targets.put("protein", plan.protein);
            targets.put("carbs", plan.carbs);
            targets.put("fat", plan.fat);
            targets.put("waterMl", plan.waterMl);
            targets.put("exerciseDays", plan.exerciseDays);
            targets.put("exerciseMinutes", plan.exerciseMinutes);
            targets.put("sleepMinutes", plan.sleepMinutes);
            sources.add(source("WEIGHT_PLAN", "plan", "PLAN_VERSION", plan.id,
                    period.start(), "健康计划第 " + plan.version + " 版", plan.updatedAt));
        }
        metrics.put("weight", weight(userId, period, sources));
        metrics.put("nutrition", nutrition(userId, period, targets, sources));
        metrics.put("hydration", hydration(userId, period, targets, sources));
        metrics.put("activity", activity(userId, period, targets, sources));
        metrics.put("sleep", sleep(userId, period, targets, sources));
        metrics.put("tasks", tasks(userId, period, sources));
        return new ReportDtos.Facts(period, plan == null ? "EMPTY" : plan.status, plan == null ? null : plan.version,
                Map.copyOf(targets), Map.copyOf(metrics), List.copyOf(sources));
    }

    private Map<String, Object> weight(String userId, ReportDtos.Period p, List<ReportDtos.Source> sources) {
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT id, weight_kg, measured_at FROM body_measurements
                WHERE user_id=? AND measured_at<? ORDER BY measured_at
                """, userId, Timestamp.from(p.queryCutoffAt()));
        List<Map<String, Object>> inPeriod = rows.stream().filter(row -> {
            Instant at = instant(row.get("measured_at"));
            return !at.isBefore(p.startInstant()) && at.isBefore(p.endExclusiveInstant());
        }).toList();
        inPeriod.forEach(row -> sources.add(source("WEIGHT_PLAN", "weight", "WEIGHT_MEASUREMENT",
                string(row, "id"), local(instant(row.get("measured_at")), p.timezone()),
                "体重记录", instant(row.get("measured_at")))));
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("count", inPeriod.size());
        if (!inPeriod.isEmpty()) {
            BigDecimal first = decimal(inPeriod.get(0).get("weight_kg"));
            BigDecimal last = decimal(inPeriod.get(inPeriod.size() - 1).get("weight_kg"));
            result.put("firstKg", first);
            result.put("latestKg", last);
            result.put("changeKg", inPeriod.size() > 1 ? last.subtract(first) : null);
        }
        if (!rows.isEmpty()) result.put("currentKg", decimal(rows.get(rows.size() - 1).get("weight_kg")));
        List<BigDecimal> goal = jdbc.query("SELECT target_weight_kg FROM health_goals WHERE user_id=?",
                (rs, n) -> rs.getBigDecimal(1), userId);
        result.put("targetKg", goal.isEmpty() ? null : goal.get(0));
        return result;
    }

    private Map<String, Object> nutrition(String userId, ReportDtos.Period p, Map<String, Object> targets,
                                           List<ReportDtos.Source> sources) {
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT id, entry_date, calories_snapshot, protein_snapshot, carbs_snapshot, fat_snapshot, updated_at
                FROM meal_entries WHERE user_id=? AND deleted_at IS NULL AND entry_date BETWEEN ? AND ? AND updated_at<=?
                ORDER BY entry_date, id
                """, userId, Date.valueOf(p.start()), Date.valueOf(p.end()), Timestamp.from(p.queryCutoffAt()));
        Map<LocalDate, BigDecimal[]> days = new LinkedHashMap<>();
        for (Map<String, Object> row : rows) {
            LocalDate date = date(row.get("entry_date"));
            BigDecimal[] sums = days.computeIfAbsent(date, ignored -> new BigDecimal[]{BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO});
            String[] columns = {"calories_snapshot", "protein_snapshot", "carbs_snapshot", "fat_snapshot"};
            for (int i = 0; i < columns.length; i++) sums[i] = sums[i].add(decimal(row.get(columns[i])));
            sources.add(source("NUTRITION", "intake", "MEAL_ENTRY", string(row, "id"), date,
                    date + " 饮食记录", instant(row.get("updated_at"))));
        }
        Map<String, Object> result = averages(days);
        int met = 0;
        Integer target = integer(targets.get("calories"));
        if (target != null) for (BigDecimal[] values : days.values())
            if (values[0].compareTo(BigDecimal.valueOf(target * .9)) >= 0 && values[0].compareTo(BigDecimal.valueOf(target * 1.1)) <= 0) met++;
        result.put("calorieTargetMetDays", target == null ? null : met);
        return result;
    }

    private Map<String, Object> hydration(String userId, ReportDtos.Period p, Map<String, Object> targets,
                                           List<ReportDtos.Source> sources) {
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT id, amount_ml, occurred_at, updated_at FROM hydration_entries
                WHERE user_id=? AND deleted_at IS NULL AND occurred_at>=? AND occurred_at<? AND updated_at<=?
                ORDER BY occurred_at, id
                """, userId, Timestamp.from(p.startInstant()), Timestamp.from(eventEnd(p)), Timestamp.from(p.queryCutoffAt()));
        Map<LocalDate, Integer> days = new LinkedHashMap<>();
        for (Map<String, Object> row : rows) {
            LocalDate date = local(instant(row.get("occurred_at")), p.timezone());
            days.merge(date, ((Number) row.get("amount_ml")).intValue(), Integer::sum);
            sources.add(source("HYDRATION", "water", "HYDRATION_ENTRY", string(row, "id"), date,
                    date + " 饮水记录", instant(row.get("updated_at"))));
        }
        int total = days.values().stream().mapToInt(Integer::intValue).sum();
        Integer target = integer(targets.get("waterMl"));
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("recordDays", days.size()); result.put("entryCount", rows.size()); result.put("totalMl", total);
        result.put("averageDailyMl", days.isEmpty() ? null : BigDecimal.valueOf(total).divide(BigDecimal.valueOf(days.size()), 1, java.math.RoundingMode.HALF_UP));
        result.put("targetMetDays", target == null ? null : days.values().stream().filter(v -> v >= target).count());
        return result;
    }

    private Map<String, Object> activity(String userId, ReportDtos.Period p, Map<String, Object> targets, List<ReportDtos.Source> sources) {
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT id, duration_minutes, final_kcal, occurred_at, updated_at FROM activity_records
                WHERE user_id=? AND deleted_at IS NULL AND occurred_at>=? AND occurred_at<? AND updated_at<=?
                ORDER BY occurred_at, id
                """, userId, Timestamp.from(p.startInstant()), Timestamp.from(eventEnd(p)), Timestamp.from(p.queryCutoffAt()));
        java.util.Set<LocalDate> days = new java.util.LinkedHashSet<>(); int minutes = 0, kcal = 0;
        for (Map<String, Object> row : rows) {
            LocalDate date = local(instant(row.get("occurred_at")), p.timezone()); days.add(date);
            minutes += ((Number) row.get("duration_minutes")).intValue(); kcal += ((Number) row.get("final_kcal")).intValue();
            sources.add(source("ACTIVITY", "exercise", "ACTIVITY_RECORD", string(row, "id"), date,
                    date + " 运动记录", instant(row.get("updated_at"))));
        }
        Integer weeklyDays = integer(targets.get("exerciseDays"));
        Integer planned = weeklyDays == null ? null : (int) Math.ceil(weeklyDays * p.eligibleDays() / 7.0);
        return linked("recordCount", rows.size(), "recordDays", days.size(), "durationMinutes", minutes, "totalKcal", kcal,
                "plannedExerciseCount", planned);
    }

    private Map<String, Object> sleep(String userId, ReportDtos.Period p, Map<String, Object> targets, List<ReportDtos.Source> sources) {
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT id, record_type, wake_local_date, duration_minutes, quality_score, updated_at FROM sleep_records
                WHERE user_id=? AND deleted_at IS NULL AND wake_local_date BETWEEN ? AND ? AND updated_at<=?
                ORDER BY wake_local_date, id
                """, userId, Date.valueOf(p.start()), Date.valueOf(p.end()), Timestamp.from(p.queryCutoffAt()));
        int nights = 0, nightMinutes = 0, naps = 0, napMinutes = 0, qualityCount = 0, qualitySum = 0, targetMet = 0;
        Integer target = integer(targets.get("sleepMinutes"));
        for (Map<String, Object> row : rows) {
            boolean night = "NIGHT".equals(string(row, "record_type")); int duration = ((Number) row.get("duration_minutes")).intValue();
            if (night) { nights++; nightMinutes += duration; if (target != null && duration >= target) targetMet++; if (row.get("quality_score") != null) { qualityCount++; qualitySum += ((Number) row.get("quality_score")).intValue(); } }
            else { naps++; napMinutes += duration; }
            LocalDate date = date(row.get("wake_local_date"));
            sources.add(source("SLEEP", night ? "night" : "nap", "SLEEP_RECORD", string(row, "id"), date,
                    date + (night ? " 夜间睡眠" : " 小睡"), instant(row.get("updated_at"))));
        }
        return linked("nightDays", nights, "averageNightMinutes", nights == 0 ? null : nightMinutes / nights,
                "qualityAverage", qualityCount == 0 ? null : BigDecimal.valueOf(qualitySum).divide(BigDecimal.valueOf(qualityCount), 1, java.math.RoundingMode.HALF_UP),
                "targetMetDays", target == null ? null : targetMet, "napCount", naps, "napMinutes", napMinutes);
    }

    private Map<String, Object> tasks(String userId, ReportDtos.Period p, List<ReportDtos.Source> sources) {
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT id, original_local_date, status, postpone_count, category, current_due_at, updated_at FROM task_instances
                WHERE user_id=? AND deleted_at IS NULL AND original_local_date BETWEEN ? AND ? AND updated_at<=?
                ORDER BY original_local_date, id
                """, userId, Date.valueOf(p.start()), Date.valueOf(p.end()), Timestamp.from(p.queryCutoffAt()));
        int completed = 0, skipped = 0, postponed = 0, overdue = 0;
        Map<String, int[]> categories = new LinkedHashMap<>();
        for (Map<String, Object> row : rows) {
            String status = string(row, "status"); if ("COMPLETED".equals(status)) completed++; if ("SKIPPED".equals(status)) skipped++;
            if (((Number) row.get("postpone_count")).intValue() > 0) postponed++;
            if ("PENDING".equals(status) && row.get("current_due_at") != null && instant(row.get("current_due_at")).isBefore(p.dataCutoffAt())) overdue++;
            int[] value = categories.computeIfAbsent(string(row, "category"), ignored -> new int[2]); value[0]++; if ("COMPLETED".equals(status)) value[1]++;
            LocalDate date = date(row.get("original_local_date"));
            sources.add(source("TASKS", "completion", "TASK_INSTANCE", string(row, "id"), date,
                    date + " 每日任务", instant(row.get("updated_at"))));
        }
        Map<String, Object> result = linked("totalCount", rows.size(), "completedCount", completed, "skippedCount", skipped,
                "postponedCount", postponed, "overdueCount", overdue,
                "completionRate", rows.isEmpty() ? null : BigDecimal.valueOf(completed * 100L).divide(BigDecimal.valueOf(rows.size()), 1, java.math.RoundingMode.HALF_UP));
        Map<String, Object> categoryMap = new LinkedHashMap<>(); categories.forEach((key, value) -> categoryMap.put(key, linked("total", value[0], "completed", value[1])));
        result.put("categories", categoryMap); return result;
    }

    private Plan plan(String userId, ReportDtos.Period period) {
        Instant cutoff = period.dataCutoffAt().isBefore(period.endExclusiveInstant())
                ? period.dataCutoffAt() : period.endExclusiveInstant();
        List<Plan> rows = jdbc.query("""
                SELECT v.id, CASE WHEN hp.risk_blocked=TRUE THEN 'RISK_BLOCKED' WHEN hp.plan_needs_recalculation=TRUE THEN 'NEEDS_RECALCULATION' ELSE p.status END,
                       v.version_number, v.target_kcal, v.protein_g, v.carbs_g, v.fat_g,
                       v.water_ml, v.exercise_days, v.exercise_minutes, v.sleep_hours, v.created_at
                FROM health_plans p JOIN health_plan_versions v ON v.plan_id=p.id
                LEFT JOIN health_profiles hp ON hp.user_id=p.user_id
                WHERE p.user_id=? AND p.phase_start_date<=? AND p.phase_end_date>=? AND v.created_at<?
                ORDER BY v.version_number DESC
                """, (rs, n) -> new Plan(rs.getString(1), rs.getString(2), rs.getInt(3), rs.getInt(4), rs.getInt(5),
                rs.getInt(6), rs.getInt(7), rs.getInt(8), rs.getInt(9), rs.getInt(10),
                rs.getBigDecimal(11).multiply(BigDecimal.valueOf(60)).intValue(), rs.getTimestamp(12).toInstant()),
                userId, Date.valueOf(period.end()), Date.valueOf(period.start()), Timestamp.from(cutoff));
        return rows.isEmpty() ? null : rows.get(0);
    }

    private static Map<String, Object> averages(Map<LocalDate, BigDecimal[]> days) {
        BigDecimal[] total = {BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO};
        days.values().forEach(values -> { for (int i = 0; i < 4; i++) total[i] = total[i].add(values[i]); });
        Map<String, Object> result = new LinkedHashMap<>(); result.put("recordDays", days.size());
        String[] names = {"averageCalories", "averageProtein", "averageCarbs", "averageFat"};
        for (int i = 0; i < 4; i++) result.put(names[i], days.isEmpty() ? null : total[i].divide(BigDecimal.valueOf(days.size()), 1, java.math.RoundingMode.HALF_UP));
        return result;
    }

    private static ReportDtos.Source source(String section, String metric, String type, String id,
                                             LocalDate date, String label, Instant updated) {
        return new ReportDtos.Source(section, metric, type, id, date, label, updated);
    }
    private static LocalDate local(Instant instant, String zone) { return instant.atZone(java.time.ZoneId.of(zone)).toLocalDate(); }
    private static Instant eventEnd(ReportDtos.Period p) { return p.dataCutoffAt().isBefore(p.endExclusiveInstant()) ? p.dataCutoffAt() : p.endExclusiveInstant(); }
    private static LocalDate date(Object value) { return value instanceof LocalDate d ? d : ((Date) value).toLocalDate(); }
    private static Instant instant(Object value) { return value instanceof Instant i ? i : ((Timestamp) value).toInstant(); }
    private static BigDecimal decimal(Object value) { return value instanceof BigDecimal d ? d : new BigDecimal(value.toString()); }
    private static Integer integer(Object value) { return value == null ? null : ((Number) value).intValue(); }
    private static String string(Map<String, Object> row, String key) { Object value = row.get(key); return value == null ? null : value.toString(); }
    private static Map<String, Object> linked(Object... values) { Map<String, Object> result = new LinkedHashMap<>(); for (int i=0;i<values.length;i+=2) result.put(values[i].toString(), values[i+1]); return result; }
    private record Plan(String id, String status, int version, int targetKcal, int protein, int carbs, int fat,
                        int waterMl, int exerciseDays, int exerciseMinutes, int sleepMinutes, Instant updatedAt) {}
}
