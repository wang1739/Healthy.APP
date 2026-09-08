package com.lightbite.healthy.plan;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;

public final class PlanDtos {

    private PlanDtos() {
    }

    public record ConfirmRequest(
            Integer targetKcal,
            Integer waterMl,
            Integer exerciseDays,
            Integer exerciseMinutes,
            BigDecimal sleepHours,
            @Size(max = 200) String reason
    ) {
        PlanCalculator.Adjustments toAdjustments() {
            return new PlanCalculator.Adjustments(
                    targetKcal, waterMl, exerciseDays, exerciseMinutes, sleepHours);
        }
    }

    public record UpdateTargetsRequest(
            @NotNull Integer expectedVersion,
            Integer targetKcal,
            Integer waterMl,
            Integer exerciseDays,
            Integer exerciseMinutes,
            BigDecimal sleepHours,
            @Size(max = 200) String reason
    ) {
        PlanCalculator.Adjustments toAdjustments() {
            return new PlanCalculator.Adjustments(
                    targetKcal, waterMl, exerciseDays, exerciseMinutes, sleepHours);
        }
    }

    public record RecalculateRequest(@NotNull Integer expectedVersion) {
    }

    public record PlanResultResponse(
            String ruleVersion,
            boolean estimated,
            BigDecimal bmi,
            int bmrKcal,
            int tdeeKcal,
            int targetKcal,
            int proteinG,
            int carbsG,
            int fatG,
            int waterMl,
            int exerciseDays,
            int exerciseMinutes,
            BigDecimal sleepHours,
            BigDecimal expectedWeeklyChangeKg,
            LocalDate suggestedTargetDate,
            String safetyMessage
    ) {
        static PlanResultResponse from(PlanCalculator.Result result) {
            return new PlanResultResponse(result.ruleVersion(), true, result.bmi(), result.bmrKcal(),
                    result.tdeeKcal(), result.targetKcal(), result.proteinG(), result.carbsG(),
                    result.fatG(), result.waterMl(), result.exerciseDays(), result.exerciseMinutes(),
                    result.sleepHours(), result.expectedWeeklyChangeKg(), result.suggestedTargetDate(),
                    result.safetyMessage());
        }
    }

    public record CurrentResponse(
            String state,
            String planId,
            Integer currentVersion,
            Integer currentWeek,
            LocalDate phaseStartDate,
            LocalDate phaseEndDate,
            Instant pausedAt,
            boolean needsRecalculation,
            PlanResultResponse plan
    ) {
        static CurrentResponse empty() {
            return new CurrentResponse("EMPTY", null, null, null, null, null, null, false, null);
        }
    }

    public record HistoryResponse(
            int versionNumber,
            String ruleVersion,
            int profileVersion,
            LocalDate calculationDate,
            int targetKcal,
            int waterMl,
            int exerciseDays,
            int exerciseMinutes,
            BigDecimal sleepHours,
            String adjustmentReason,
            Instant createdAt
    ) {
    }
}
