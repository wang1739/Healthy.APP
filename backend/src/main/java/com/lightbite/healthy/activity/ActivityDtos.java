package com.lightbite.healthy.activity;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;

public final class ActivityDtos {

    private ActivityDtos() {
    }

    public record TypeResponse(
            String id, String name, String category,
            BigDecimal lowMet, BigDecimal mediumMet, BigDecimal highMet,
            String typeScope, String referenceTypeId
    ) {
    }

    public record CustomTypeRequest(String name, String referenceTypeId) {
    }

    public record RecordRequest(
            String activityTypeId,
            String intensity,
            int durationMinutes,
            OffsetDateTime occurredAt,
            String timezone,
            String calorieMode,
            Integer finalKcal
    ) {
    }

    public record RecordResponse(
            String id,
            TypeResponse activityType,
            String activityName,
            String intensity,
            int durationMinutes,
            Instant occurredAt,
            String timezone,
            BigDecimal weightKgSnapshot,
            BigDecimal metSnapshot,
            String calculationVersion,
            int estimatedKcal,
            int finalKcal,
            String calorieSource,
            String source
    ) {
    }

    public record DayResponse(
            LocalDate date,
            String status,
            List<RecordResponse> records,
            int recordCount,
            int totalDurationMinutes,
            int totalKcal,
            BigDecimal weightKg,
            String cacheVersion
    ) {
    }

    public record WeekResponse(
            LocalDate startDate,
            LocalDate endDate,
            String status,
            int exerciseDays,
            int durationMinutes,
            int totalKcal,
            Integer targetExerciseDays,
            Integer targetDurationMinutes,
            String planState
    ) {
    }

    public record MutationResponse(
            RecordResponse record,
            DayResponse day,
            WeekResponse week
    ) {
    }

    public record TodaySummary(DayResponse day, WeekResponse week) {
    }
}
