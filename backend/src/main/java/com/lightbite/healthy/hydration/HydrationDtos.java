package com.lightbite.healthy.hydration;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;

public final class HydrationDtos {

    private HydrationDtos() {
    }

    public record SettingsRequest(
            Integer dailyTargetMl,
            Integer defaultCupMl,
            Boolean reminderEnabled,
            String reminderStartTime,
            String reminderEndTime,
            Integer reminderIntervalMinutes,
            String quietStartTime,
            String quietEndTime,
            Integer version
    ) {
    }

    public record SettingsResponse(
            Integer dailyTargetMl,
            int effectiveTargetMl,
            int defaultCupMl,
            boolean reminderEnabled,
            String reminderStartTime,
            String reminderEndTime,
            int reminderIntervalMinutes,
            String quietStartTime,
            String quietEndTime,
            String targetSource,
            Integer currentPlanTargetMl,
            Integer sourcePlanVersion,
            boolean planTargetChanged,
            int version
    ) {
    }

    public record EntryRequest(int amountMl, OffsetDateTime occurredAt, String timezone, String source) {
    }

    public record EntryResponse(
            String id,
            int amountMl,
            Instant occurredAt,
            String timezone,
            String source
    ) {
    }

    public record DayResponse(
            LocalDate date,
            String status,
            List<EntryResponse> entries,
            int totalMl,
            int targetMl,
            int remainingMl,
            BigDecimal progress,
            String targetSource,
            SettingsResponse settings
    ) {
    }
}
