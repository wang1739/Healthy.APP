package com.lightbite.healthy.plan;

import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.lightbite.healthy.common.api.ApiException;
import java.math.BigDecimal;
import java.time.LocalDate;
import org.junit.jupiter.api.Test;

class PlanPolicyTests {

    private final PlanPolicy policy = new PlanPolicy();

    @Test
    void blocksOtherSexWithoutMetabolicBasis() {
        assertThatThrownBy(() -> policy.validateProfile(profile("OTHER", null, "FAT_LOSS", false)))
                .isInstanceOf(ApiException.class)
                .extracting("code").isEqualTo("METABOLIC_BASIS_REQUIRED");
    }

    @Test
    void blocksRiskUnsupportedGoalAndUnderweight() {
        assertThatThrownBy(() -> policy.validateProfile(profile("FEMALE", "FEMALE", "FAT_LOSS", true)))
                .extracting("code").isEqualTo("PLAN_RISK_BLOCKED");
        assertThatThrownBy(() -> policy.validateProfile(profile("FEMALE", "FEMALE", "MAINTAIN", false)))
                .extracting("code").isEqualTo("PLAN_GOAL_UNSUPPORTED");
        PlanPolicy.ProfileSnapshot underweight = new PlanPolicy.ProfileSnapshot(
                true, false, 30, "FEMALE", "FEMALE", new BigDecimal("180"),
                new BigDecimal("55"), "LIGHT", new BigDecimal("7"), 2, "FAT_LOSS",
                new BigDecimal("50"), LocalDate.of(2027, 1, 1), 1);
        assertThatThrownBy(() -> policy.validateProfile(underweight))
                .extracting("code").isEqualTo("PLAN_BMI_UNSAFE");
    }

    @Test
    void rejectsUnsafeAdjustmentStepsAndRanges() {
        assertThatThrownBy(() -> policy.validateAdjustments(
                new PlanCalculator.Adjustments(1475, 2000, 3, 150, new BigDecimal("8"))))
                .extracting("code").isEqualTo("INVALID_TARGET_KCAL_STEP");
        assertThatThrownBy(() -> policy.validateAdjustments(
                new PlanCalculator.Adjustments(1500, 3600, 3, 150, new BigDecimal("8"))))
                .extracting("code").isEqualTo("INVALID_WATER_TARGET");
    }

    private PlanPolicy.ProfileSnapshot profile(String sex, String basis, String goal, boolean blocked) {
        return new PlanPolicy.ProfileSnapshot(true, blocked, 31, sex, basis, new BigDecimal("165"),
                new BigDecimal("62.5"), "LIGHT", new BigDecimal("7.5"), 2, goal,
                new BigDecimal("55"), LocalDate.of(2027, 1, 1), 3);
    }
}
