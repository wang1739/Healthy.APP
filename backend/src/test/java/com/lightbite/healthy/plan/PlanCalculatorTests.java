package com.lightbite.healthy.plan;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.math.BigDecimal;
import java.time.LocalDate;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

class PlanCalculatorTests {

    private final PlanCalculator calculator = new PlanCalculator();

    @ParameterizedTest
    @CsvSource({"LOW,1608", "LIGHT,1843", "MODERATE,2077", "HIGH,2312"})
    void appliesEveryVersionedActivityFactor(String activityLevel, int expectedTdee) {
        PlanCalculator.Result result = calculator.calculate(new PlanCalculator.Input(
                31, "FEMALE", new BigDecimal("165"), new BigDecimal("62.5"), activityLevel,
                new BigDecimal("55"), LocalDate.of(2027, 6, 1), new BigDecimal("7.5"), 2,
                LocalDate.of(2026, 9, 8), null));

        assertThat(result.tdeeKcal()).isEqualTo(expectedTdee);
    }

    @Test
    void calculatesFemaleLightActivityPlanWithAuthoritativeRounding() {
        PlanCalculator.Result result = calculator.calculate(new PlanCalculator.Input(
                31, "FEMALE", new BigDecimal("165"), new BigDecimal("62.5"), "LIGHT",
                new BigDecimal("55"), LocalDate.of(2026, 12, 1), new BigDecimal("7.5"), 2,
                LocalDate.of(2026, 9, 8), null));

        assertThat(result.ruleVersion()).isEqualTo("FAT_LOSS_V1");
        assertThat(result.bmi()).isEqualByComparingTo("23.0");
        assertThat(result.bmrKcal()).isEqualTo(1340);
        assertThat(result.tdeeKcal()).isEqualTo(1843);
        assertThat(result.targetKcal()).isEqualTo(1470);
        assertThat(result.proteinG()).isEqualTo(92);
        assertThat(result.carbsG()).isEqualTo(184);
        assertThat(result.fatG()).isEqualTo(41);
        assertThat(result.waterMl()).isEqualTo(1900);
        assertThat(result.exerciseDays()).isEqualTo(3);
        assertThat(result.exerciseMinutes()).isEqualTo(150);
        assertThat(result.sleepHours()).isEqualByComparingTo("7.5");
        assertThat(result.expectedWeeklyChangeKg()).isEqualByComparingTo("0.34");
        assertThat(result.suggestedTargetDate()).isEqualTo(LocalDate.of(2027, 2, 16));
    }

    @Test
    void enforcesMaleFloorAndOnePercentWeeklyLimitBeforeDisplayRounding() {
        PlanCalculator.Result floor = calculator.calculate(new PlanCalculator.Input(
                40, "MALE", new BigDecimal("170"), new BigDecimal("50"), "LOW",
                new BigDecimal("48"), LocalDate.of(2027, 1, 1), new BigDecimal("6"), 0,
                LocalDate.of(2026, 9, 8), null));
        assertThat(floor.targetKcal()).isEqualTo(1500);

        PlanCalculator.Result weeklyLimit = calculator.calculate(new PlanCalculator.Input(
                30, "MALE", new BigDecimal("190"), new BigDecimal("60"), "HIGH",
                new BigDecimal("55"), LocalDate.of(2026, 10, 1), new BigDecimal("8"), 5,
                LocalDate.of(2026, 9, 8), null));
        assertThat(weeklyLimit.expectedWeeklyChangeKg()).isLessThanOrEqualTo(new BigDecimal("0.60"));

        assertThatThrownBy(() -> calculator.calculate(new PlanCalculator.Input(
                40, "MALE", new BigDecimal("170"), new BigDecimal("50"), "LOW",
                new BigDecimal("48"), LocalDate.of(2027, 1, 1), new BigDecimal("6"), 0,
                LocalDate.of(2026, 9, 8), new PlanCalculator.Adjustments(
                        1450, null, null, null, null))))
                .extracting("code").isEqualTo("TARGET_KCAL_UNSAFE");
    }

    @Test
    void appliesOnlySupportedAdjustmentsAndRecomputesMacros() {
        PlanCalculator.Result result = calculator.calculate(new PlanCalculator.Input(
                31, "FEMALE", new BigDecimal("165"), new BigDecimal("62.5"), "LIGHT",
                new BigDecimal("55"), LocalDate.of(2027, 3, 1), new BigDecimal("6"), 1,
                LocalDate.of(2026, 9, 8), new PlanCalculator.Adjustments(
                        1500, 2200, 4, 180, new BigDecimal("8.0"))));

        assertThat(result.targetKcal()).isEqualTo(1500);
        assertThat(result.proteinG()).isEqualTo(94);
        assertThat(result.waterMl()).isEqualTo(2200);
        assertThat(result.exerciseDays()).isEqualTo(4);
        assertThat(result.exerciseMinutes()).isEqualTo(180);
        assertThat(result.sleepHours()).isEqualByComparingTo("8.0");
    }
}
