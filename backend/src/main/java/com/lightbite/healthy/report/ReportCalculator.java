package com.lightbite.healthy.report;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

@Component
public class ReportCalculator {
    public static final String RULES_VERSION = "REPORT_RULES_V1";
    private static final List<String> CODES = List.of("weight", "nutrition", "hydration", "activity", "sleep", "tasks");
    private static final Map<String, String> TITLES = Map.of(
            "weight", "体重与计划", "nutrition", "饮食", "hydration", "饮水",
            "activity", "运动", "sleep", "睡眠", "tasks", "每日任务");

    public ReportDtos.Snapshot calculate(ReportDtos.Facts facts, ReportDtos.Facts previous, String displayName) {
        List<ReportDtos.Section> sections = new ArrayList<>();
        for (String code : CODES) sections.add(section(code, facts, previous));
        long sufficient = sections.stream().filter(s -> "SUFFICIENT".equals(s.sufficiency())).count();
        List<ReportDtos.Advice> advice = advice(sections);
        Map<String, Object> period = linked("type", facts.period().type(), "start", facts.period().start(),
                "end", facts.period().end(), "timezone", facts.period().timezone(), "status", facts.period().status());
        List<Map<String, Object>> keys = List.of(
                linked("label", "数据充分栏目", "value", sufficient, "unit", "/6"),
                linked("label", "记录覆盖天数", "value", facts.period().eligibleDays(), "unit", "天"));
        return new ReportDtos.Snapshot(period, blank(displayName) ? "用户" : displayName,
                "本周期有 " + sufficient + " 个栏目数据充分。", keys, sections,
                linked("sufficientSections", sufficient, "totalSections", 6), advice,
                RULES_VERSION, facts.period().dataCutoffAt(), "本报告仅用于健康记录回顾，不构成医疗诊断或治疗建议。");
    }

    private ReportDtos.Section section(String code, ReportDtos.Facts facts, ReportDtos.Facts previous) {
        Map<String, Object> metrics = map(facts.metrics().get(code));
        int expected = facts.period().eligibleDays();
        int count = switch (code) {
            case "weight" -> number(metrics.get("count"));
            case "nutrition", "hydration" -> number(metrics.get("recordDays"));
            case "activity" -> number(metrics.get("recordCount"));
            case "sleep" -> number(metrics.get("nightDays"));
            case "tasks" -> number(metrics.get("totalCount"));
            default -> 0;
        };
        String status = sufficiency(code, facts, metrics, count, expected);
        String reason = switch (status) {
            case "SUFFICIENT" -> "已有足够记录用于本周期汇总";
            case "LIMITED" -> "记录较少，仅展示可以确认的事实";
            case "NOT_APPLICABLE" -> "本周期没有应执行任务";
            default -> "本周期暂无记录";
        };
        Map<String, Object> target = activePlan(facts) ? targetComparison(code, facts, metrics) : Map.of("status", "NOT_APPLICABLE", "reason", "当前没有可执行计划");
        Map<String, Object> prior = previousComparison(code, status, metrics, previous);
        return new ReportDtos.Section(code.toUpperCase(), TITLES.get(code), status, reason, count, expected,
                metrics, target, prior);
    }

    private String sufficiency(String code, ReportDtos.Facts facts, Map<String, Object> metrics, int count, int expected) {
        String status;
        if ("tasks".equals(code)) status = count == 0 ? "NOT_APPLICABLE" : "SUFFICIENT";
        else if (facts.period().type().equals("DAILY")) {
            if ("weight".equals(code)) status = count == 0 ? "EMPTY" : count == 1 ? "LIMITED" : "SUFFICIENT";
            else status = count == 0 ? "EMPTY" : "SUFFICIENT";
        } else if ("weight".equals(code)) status = count == 0 ? "EMPTY" : count == 1 ? "LIMITED" : "SUFFICIENT";
        else if ("activity".equals(code)) {
            Integer planned = activePlan(facts) ? integer(metrics.get("plannedExerciseCount")) : null;
            int threshold = planned == null ? 2 : (int) Math.ceil(planned * .5);
            status = count == 0 ? "EMPTY" : count >= threshold ? "SUFFICIENT" : "LIMITED";
        } else {
            int threshold = (int) Math.ceil(expected * .5);
            status = count == 0 ? "EMPTY" : count >= threshold ? "SUFFICIENT" : "LIMITED";
        }
        return status;
    }

    private Map<String, Object> targetComparison(String code, ReportDtos.Facts facts, Map<String, Object> metrics) {
        Object actual; Object target;
        switch (code) {
            case "nutrition" -> { actual = metrics.get("averageCalories"); target = facts.targets().get("calories"); }
            case "hydration" -> { actual = metrics.get("averageDailyMl"); target = facts.targets().get("waterMl"); }
            case "activity" -> { actual = metrics.get("durationMinutes"); target = facts.targets().get("exerciseMinutes"); }
            case "sleep" -> { actual = metrics.get("averageNightMinutes"); target = facts.targets().get("sleepMinutes"); }
            case "weight" -> { actual = metrics.get("currentKg"); target = metrics.get("targetKg"); }
            default -> { return Map.of("status", "NOT_APPLICABLE", "reason", "该栏目没有计划目标"); }
        }
        if (actual == null || target == null) return Map.of("status", "NOT_APPLICABLE", "reason", "缺少可比较的目标或记录");
        BigDecimal difference = decimal(actual).subtract(decimal(target));
        return linked("status", "AVAILABLE", "actual", actual, "target", target, "difference", difference);
    }

    private Map<String, Object> previousComparison(String code, String status, Map<String, Object> current, ReportDtos.Facts previous) {
        if (previous == null || !"SUFFICIENT".equals(status)) return Map.of("status", "UNAVAILABLE", "reason", "当前或上一周期数据不足");
        Map<String, Object> prior = map(previous.metrics().get(code));
        int priorCount = switch (code) {
            case "weight" -> number(prior.get("count")); case "nutrition", "hydration" -> number(prior.get("recordDays"));
            case "activity" -> number(prior.get("recordCount")); case "sleep" -> number(prior.get("nightDays")); default -> number(prior.get("totalCount"));
        };
        if (!"SUFFICIENT".equals(sufficiency(code, previous, prior, priorCount, previous.period().eligibleDays())))
            return Map.of("status", "UNAVAILABLE", "reason", "上一周期数据不足");
        String metric = switch (code) {
            case "weight" -> "latestKg"; case "nutrition" -> "averageCalories"; case "hydration" -> "averageDailyMl";
            case "activity" -> "durationMinutes"; case "sleep" -> "averageNightMinutes"; default -> "completionRate";
        };
        if (current.get(metric) == null || prior.get(metric) == null) return Map.of("status", "UNAVAILABLE", "reason", "上一周期数据不足");
        BigDecimal delta = decimal(current.get(metric)).subtract(decimal(prior.get(metric)));
        return linked("status", "AVAILABLE", "metric", metric, "current", current.get(metric), "previous", prior.get(metric),
                "difference", delta, "direction", delta.signum() == 0 ? "持平" : delta.signum() > 0 ? "上升" : "下降");
    }

    private List<ReportDtos.Advice> advice(List<ReportDtos.Section> sections) {
        List<ReportDtos.Advice> result = new ArrayList<>();
        for (ReportDtos.Section section : sections) if ("LIMITED".equals(section.sufficiency()) || "EMPTY".equals(section.sufficiency()))
            result.add(new ReportDtos.Advice("DATA_GAP_" + section.code(), "继续记录" + section.title(),
                    section.reason() + "，继续记录会让下次报告更准确。", section.code() + ".recordDays", 1));
        sections.stream().filter(s -> List.of("NUTRITION", "HYDRATION", "ACTIVITY", "SLEEP").contains(s.code()))
                .filter(s -> "SUFFICIENT".equals(s.sufficiency()) && "AVAILABLE".equals(s.targetComparison().get("status")))
                .max(Comparator.comparing(this::targetGap).thenComparing(ReportDtos.Section::code))
                .ifPresent(s -> result.add(new ReportDtos.Advice("PLAN_GAP_" + s.code(), "关注" + s.title() + "目标差距",
                        "本周期该项与计划目标仍有差距，可以从下一次记录开始逐步调整。", s.code() + ".targetDifference", 2)));
        sections.stream().filter(s -> "TASKS".equals(s.code()) && "SUFFICIENT".equals(s.sufficiency()) && number(s.metrics().get("postponedCount")) > 0)
                .findFirst().ifPresent(s -> result.add(new ReportDtos.Advice("CONTINUITY_TASK_POSTPONED", "留意任务延期",
                        "本周期有 " + s.metrics().get("postponedCount") + " 项任务发生延期，可以调整经常延期任务的执行时间。", "TASKS.postponedCount", 3)));
        if (result.isEmpty()) result.add(new ReportDtos.Advice("POSITIVE_RECORDING", "保持记录习惯", "本周期记录较完整，可以继续保持。", "completeness.sufficientSections", 4));
        return result.stream().sorted(Comparator.comparingInt(ReportDtos.Advice::priority).thenComparing(ReportDtos.Advice::code)).limit(3).toList();
    }

    private BigDecimal targetGap(ReportDtos.Section section) {
        BigDecimal target = decimal(section.targetComparison().get("target"));
        return target.signum() == 0 ? BigDecimal.ZERO : decimal(section.targetComparison().get("difference")).abs()
                .divide(target.abs(), 6, java.math.RoundingMode.HALF_UP);
    }

    private static boolean activePlan(ReportDtos.Facts facts) { return "ACTIVE".equals(facts.planState()); }
    @SuppressWarnings("unchecked") private static Map<String, Object> map(Object value) { return value == null ? new LinkedHashMap<>() : new LinkedHashMap<>((Map<String, Object>) value); }
    private static int number(Object value) { return value == null ? 0 : ((Number) value).intValue(); }
    private static Integer integer(Object value) { return value == null ? null : ((Number) value).intValue(); }
    private static BigDecimal decimal(Object value) { return value instanceof BigDecimal d ? d : new BigDecimal(value.toString()); }
    private static boolean blank(String value) { return value == null || value.isBlank(); }
    private static Map<String, Object> linked(Object... values) { Map<String, Object> result = new LinkedHashMap<>(); for (int i=0;i<values.length;i+=2) result.put(values[i].toString(), values[i+1]); return result; }
}
