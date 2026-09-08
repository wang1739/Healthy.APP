package com.lightbite.healthy.plan;

import com.lightbite.healthy.common.api.ApiException;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

@Component
public class PlanPolicy {

    public void validateProfile(ProfileSnapshot profile) {
        if (!profile.complete()) {
            fail("PROFILE_INCOMPLETE", "请先完成全部健康档案步骤");
        }
        if (profile.heightCm() == null || profile.weightKg() == null || profile.activityLevel() == null
                || profile.sleepHours() == null || profile.goalType() == null) {
            fail("PROFILE_INCOMPLETE", "健康档案缺少生成计划所需的信息");
        }
        if (profile.riskBlocked()) {
            fail("PLAN_RISK_BLOCKED", "当前情况不适合自动生成普通减脂计划，请咨询医生或注册营养师");
        }
        if (!"FAT_LOSS".equals(profile.goalType())) {
            fail("PLAN_GOAL_UNSUPPORTED", "当前目标的个性计划尚未开放");
        }
        if (profile.age() < 18) {
            fail("PLAN_AGE_UNSUPPORTED", "未成年人不适合使用普通减脂计划");
        }
        if (profile.metabolicBasis() == null ||
                !(profile.metabolicBasis().equals("MALE") || profile.metabolicBasis().equals("FEMALE"))) {
            fail("METABOLIC_BASIS_REQUIRED", "请选择男性公式或女性公式作为代谢计算依据");
        }
        BigDecimal bmi = bmi(profile.weightKg(), profile.heightCm());
        if (bmi.compareTo(new BigDecimal("18.5")) < 0) {
            fail("PLAN_BMI_UNSAFE", "当前体重不适合生成普通减脂计划");
        }
        if (profile.targetWeightKg() == null || profile.targetWeightKg().compareTo(profile.weightKg()) >= 0
                || bmi(profile.targetWeightKg(), profile.heightCm()).compareTo(new BigDecimal("18.5")) < 0) {
            fail("PLAN_TARGET_UNSAFE", "目标体重不在安全减脂范围内");
        }
        if (profile.targetDate() == null || !profile.targetDate().isAfter(LocalDate.now())) {
            fail("PLAN_TARGET_DATE_INVALID", "目标日期必须晚于今天");
        }
    }

    public void validateAdjustments(PlanCalculator.Adjustments adjustments) {
        if (adjustments == null) {
            return;
        }
        if (adjustments.waterMl() != null && (adjustments.waterMl() < 1500
                || adjustments.waterMl() > 3500 || adjustments.waterMl() % 100 != 0)) {
            badRequest("INVALID_WATER_TARGET", "饮水目标需在 1500 至 3500 毫升之间并按 100 毫升调整");
        }
        if (adjustments.exerciseDays() != null && (adjustments.exerciseDays() < 0 || adjustments.exerciseDays() > 7)) {
            badRequest("INVALID_EXERCISE_DAYS", "每周运动天数需在 0 至 7 天之间");
        }
        if (adjustments.exerciseMinutes() != null && (adjustments.exerciseMinutes() < 0
                || adjustments.exerciseMinutes() % 30 != 0)) {
            badRequest("INVALID_EXERCISE_MINUTES", "运动时长必须按 30 分钟调整");
        }
        if (adjustments.sleepHours() != null && (adjustments.sleepHours().compareTo(new BigDecimal("7")) < 0
                || adjustments.sleepHours().compareTo(new BigDecimal("9")) > 0
                || adjustments.sleepHours().multiply(new BigDecimal("2")).stripTrailingZeros().scale() > 0)) {
            badRequest("INVALID_SLEEP_TARGET", "睡眠目标需在 7 至 9 小时之间并按 0.5 小时调整");
        }
    }

    public void validateTargetKcalStep(Integer targetKcal, int baselineKcal) {
        if (targetKcal != null && Math.abs((long) targetKcal - baselineKcal) % 50 != 0) {
            badRequest("INVALID_TARGET_KCAL_STEP", "目标热量必须按 50 千卡调整");
        }
    }

    private BigDecimal bmi(BigDecimal weight, BigDecimal heightCm) {
        BigDecimal metres = heightCm.divide(new BigDecimal("100"));
        return weight.divide(metres.multiply(metres), 8, RoundingMode.HALF_UP);
    }

    private void fail(String code, String message) {
        throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, code, message);
    }

    private void badRequest(String code, String message) {
        throw new ApiException(HttpStatus.BAD_REQUEST, code, message);
    }

    public record ProfileSnapshot(
            boolean complete,
            boolean riskBlocked,
            int age,
            String sex,
            String metabolicBasis,
            BigDecimal heightCm,
            BigDecimal weightKg,
            String activityLevel,
            BigDecimal sleepHours,
            int exerciseDays,
            String goalType,
            BigDecimal targetWeightKg,
            LocalDate targetDate,
            int profileVersion
    ) {
    }
}
