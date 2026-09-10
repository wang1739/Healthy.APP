package com.lightbite.healthy.today;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;

public final class TodayDtos {

    private TodayDtos() {
    }

    public enum ModuleStatus {
        READY, EMPTY, PROFILE_INCOMPLETE, NO_PLAN, PAUSED, NEEDS_RECALCULATION, RISK_BLOCKED,
        COMING_SOON, ERROR
    }

    public record PlanModule(
            ModuleStatus status,
            String state,
            Integer currentWeek,
            Integer targetKcal,
            Integer proteinG,
            Integer carbsG,
            Integer fatG,
            Integer waterMl,
            Integer exerciseDays,
            Integer exerciseMinutes,
            BigDecimal sleepHours,
            String message
    ) {
    }

    public record WeightModule(
            ModuleStatus status,
            BigDecimal valueKg,
            Instant measuredAt,
            String message
    ) {
    }

    public record Module(ModuleStatus status, String message) {
    }

    public record TaskNextTask(
            String id,
            String title,
            Instant dueAt,
            LocalDate date,
            String category,
            String source,
            boolean allDay
    ) {
    }

    public record TaskModule(
            ModuleStatus status,
            Integer totalCount,
            Integer completedCount,
            Integer pendingCount,
            Integer overdueCount,
            TaskNextTask nextTask,
            Boolean hasPlanUpdate,
            String healthGuide,
            String message
    ) {
    }

    public record NutritionModule(
            ModuleStatus status,
            Integer consumedKcal,
            Integer targetKcal,
            BigDecimal proteinG,
            BigDecimal carbsG,
            BigDecimal fatG,
            String message
    ) {
    }

    public record HydrationModule(
            ModuleStatus status,
            Integer consumedMl,
            Integer targetMl,
            Integer remainingMl,
            BigDecimal progress,
            String message
    ) {
    }

    public record ActivityModule(
            ModuleStatus status,
            Integer todayDurationMinutes,
            Integer todayKcal,
            Integer todayRecordCount,
            Integer weekExerciseDays,
            Integer weekDurationMinutes,
            Integer targetExerciseDays,
            Integer targetDurationMinutes,
            String message
    ) {
    }

    public record SleepModule(
            ModuleStatus status,
            Integer nightDurationMinutes,
            Integer targetMinutes,
            Integer differenceMinutes,
            Integer qualityScore,
            String qualityLabel,
            Integer napDurationMinutes,
            Boolean hasEnoughTrendData,
            String message
    ) {
    }

    public record NextAction(String type, String title) {
    }

    public record TodayResponse(
            LocalDate date,
            PlanModule plan,
            WeightModule weight,
            NutritionModule nutrition,
            HydrationModule hydration,
            ActivityModule activity,
            SleepModule sleep,
            TaskModule tasks,
            NextAction nextAction
    ) {
    }
}
