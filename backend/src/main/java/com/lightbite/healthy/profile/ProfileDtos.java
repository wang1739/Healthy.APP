package com.lightbite.healthy.profile;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
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
            String metabolicBasis,
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
            @Size(max = 500) String avoidFoods,
            @Min(0) Long expectedVersion
    ) {
    }

    public record RiskRequest(
            @Min(0) Long expectedVersion,
            @NotNull Boolean pregnant,
            @NotNull Boolean breastfeeding,
            @NotNull Boolean eatingDisorderRisk,
            @NotNull Boolean seriousChronicDisease,
            @NotNull Boolean unsafeTarget
    ) {
    }

    public record RiskResponse(boolean riskBlocked, String message) {
    }

    public record CompletenessResponse(
            int currentStep,
            int percentage,
            boolean complete,
            boolean riskBlocked,
            boolean planNeedsRecalculation,
            boolean metabolicBasisRequired,
            String sex,
            String metabolicBasis,
            LocalDate birthDate
    ) {
    }

    public record BasicInfoRequest(
            @NotNull @Min(0) Long expectedVersion,
            LocalDate birthDate,
            String sex,
            String metabolicBasis
    ) {
    }

    public record BodyDataRequest(
            @NotNull @Min(0) Long expectedVersion,
            @DecimalMin("100") @DecimalMax("230") BigDecimal heightCm,
            @DecimalMin("30") @DecimalMax("300") BigDecimal weightKg,
            @DecimalMin("40") @DecimalMax("200") BigDecimal waistCm,
            @DecimalMin("2") @DecimalMax("70") BigDecimal bodyFatPercent
    ) {
    }

    public record LifestyleRequest(
            @NotNull @Min(0) Long expectedVersion,
            String activityLevel,
            String workStyle,
            @DecimalMin("0") @DecimalMax("24") BigDecimal sleepHours,
            @Min(0) @Max(7) Integer exerciseDays
    ) {
    }

    public record HealthGoalRequest(
            @NotNull @Min(0) Long expectedVersion,
            String goalType,
            @DecimalMin("30") @DecimalMax("300") BigDecimal targetWeightKg,
            LocalDate targetDate
    ) {
    }

    public record BasicInfoResponse(LocalDate birthDate, String sex, String metabolicBasis) {
    }

    public record BodyDataResponse(BigDecimal heightCm, MeasurementResponse latestMeasurement) {
    }

    public record LifestyleResponse(
            String activityLevel, String workStyle, BigDecimal sleepHours, Integer exerciseDays
    ) {
    }

    public record DietaryPreferencesResponse(String dietType, String allergies, String avoidFoods) {
    }

    public record HealthGoalResponse(String goalType, BigDecimal targetWeightKg, LocalDate targetDate) {
    }

    public record RiskInfoResponse(
            boolean pregnant,
            boolean breastfeeding,
            boolean eatingDisorderRisk,
            boolean seriousChronicDisease,
            boolean unsafeTarget,
            boolean riskBlocked
    ) {
    }

    public record ProfileSectionsResponse(
            BasicInfoResponse basicInfo,
            BodyDataResponse bodyData,
            LifestyleResponse lifestyle,
            DietaryPreferencesResponse dietaryPreferences,
            HealthGoalResponse healthGoal,
            RiskInfoResponse riskInfo,
            boolean complete,
            boolean planNeedsRecalculation,
            long profileVersion
    ) {
    }
}
