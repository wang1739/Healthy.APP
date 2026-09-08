package com.lightbite.healthy.today;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;

public final class TodayDtos {

    private TodayDtos() {
    }

    public enum ModuleStatus {
        READY, EMPTY, COMING_SOON, ERROR
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

    public record NextAction(String type, String title) {
    }

    public record TodayResponse(
            LocalDate date,
            PlanModule plan,
            WeightModule weight,
            Module nutrition,
            Module hydration,
            Module activity,
            Module sleep,
            Module tasks,
            NextAction nextAction
    ) {
    }
}
