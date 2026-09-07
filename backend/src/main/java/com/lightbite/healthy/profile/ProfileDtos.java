package com.lightbite.healthy.profile;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;

public final class ProfileDtos {

    private ProfileDtos() {
    }

    public record ProfileRequest(
            LocalDate birthDate,
            String sex,
            @DecimalMin("100") @DecimalMax("230") BigDecimal heightCm,
            String activityLevel,
            String workStyle,
            @DecimalMin("0") @DecimalMax("24") BigDecimal sleepHours,
            @Min(0) @Max(7) Integer exerciseDays,
            String goalType,
            @DecimalMin("30") @DecimalMax("300") BigDecimal targetWeightKg,
            LocalDate targetDate,
            @Min(0) @Max(7) Integer currentStep,
            Boolean completed
    ) {
    }

    public record MeasurementRequest(
            @DecimalMin("30") @DecimalMax("300") BigDecimal weightKg,
            @DecimalMin("40") @DecimalMax("200") BigDecimal waistCm,
            @DecimalMin("2") @DecimalMax("70") BigDecimal bodyFatPercent
    ) {
    }

    public record MeasurementResponse(
            String id,
            BigDecimal weightKg,
            BigDecimal waistCm,
            BigDecimal bodyFatPercent,
            Instant measuredAt
    ) {
    }

    public record PreferencesRequest(
            @Size(max = 24) String dietType,
            @Size(max = 500) String allergies,
            @Size(max = 500) String avoidFoods
    ) {
    }

    public record RiskRequest(
            boolean pregnant,
            boolean breastfeeding,
            boolean eatingDisorderRisk,
            boolean seriousChronicDisease,
            boolean unsafeTarget
    ) {
    }

    public record RiskResponse(boolean riskBlocked, String message) {
    }

    public record CompletenessResponse(
            int currentStep,
            int percentage,
            boolean complete,
            boolean riskBlocked,
            boolean planNeedsRecalculation
    ) {
    }
}
