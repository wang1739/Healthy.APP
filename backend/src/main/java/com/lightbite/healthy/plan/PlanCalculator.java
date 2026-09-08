package com.lightbite.healthy.plan;

import com.lightbite.healthy.common.api.ApiException;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

@Component
public class PlanCalculator {

    public static final String RULE_VERSION = "FAT_LOSS_V1";
    private static final BigDecimal SEVEN = new BigDecimal("7");
    private static final BigDecimal ENERGY_PER_KG = new BigDecimal("7700");

    public Result calculate(Input input) {
        BigDecimal heightMetres = input.heightCm().divide(new BigDecimal("100"));
        BigDecimal bmiRaw = input.weightKg().divide(heightMetres.multiply(heightMetres), 12, RoundingMode.HALF_UP);
        BigDecimal bmrRaw = input.weightKg().multiply(BigDecimal.TEN)
                .add(input.heightCm().multiply(new BigDecimal("6.25")))
                .subtract(BigDecimal.valueOf(input.age()).multiply(new BigDecimal("5")))
                .add("MALE".equals(input.metabolicBasis()) ? new BigDecimal("5") : new BigDecimal("-161"));
        BigDecimal tdeeRaw = bmrRaw.multiply(activityFactor(input.activityLevel()));
        BigDecimal weeklyLimitFloor = tdeeRaw.subtract(
                input.weightKg().multiply(new BigDecimal("0.01")).multiply(ENERGY_PER_KG).divide(SEVEN, 12, RoundingMode.HALF_UP));
        BigDecimal minimum = max(
                bmrRaw,
                "MALE".equals(input.metabolicBasis()) ? new BigDecimal("1500") : new BigDecimal("1200"),
                tdeeRaw.subtract(new BigDecimal("750")),
                weeklyLimitFloor
        );
        BigDecimal generated = max(tdeeRaw.multiply(new BigDecimal("0.80")), minimum);
        BigDecimal targetRaw = input.adjustments() != null && input.adjustments().targetKcal() != null
                ? BigDecimal.valueOf(input.adjustments().targetKcal()) : generated;
        if (targetRaw.compareTo(minimum) < 0 || targetRaw.compareTo(tdeeRaw) >= 0) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "TARGET_KCAL_UNSAFE",
                    "目标热量超出当前安全范围");
        }

        int targetKcal = input.adjustments() != null && input.adjustments().targetKcal() != null
                ? input.adjustments().targetKcal() : roundTo(targetRaw, 10);
        int waterMl = input.adjustments() != null && input.adjustments().waterMl() != null
                ? input.adjustments().waterMl()
                : Math.max(1500, Math.min(3500, roundTo(input.weightKg().multiply(new BigDecimal("30")), 100)));
        int exerciseDays = input.adjustments() != null && input.adjustments().exerciseDays() != null
                ? input.adjustments().exerciseDays() : Math.max(3, input.currentExerciseDays());
        int exerciseMinutes = input.adjustments() != null && input.adjustments().exerciseMinutes() != null
                ? input.adjustments().exerciseMinutes() : 150;
        BigDecimal sleepHours = input.adjustments() != null && input.adjustments().sleepHours() != null
                ? input.adjustments().sleepHours() : nearestHalf(clamp(input.currentSleepHours(), "7", "9"));
        BigDecimal expectedWeekly = tdeeRaw.subtract(BigDecimal.valueOf(targetKcal))
                .multiply(SEVEN).divide(ENERGY_PER_KG, 12, RoundingMode.HALF_UP);
        long weeks = input.weightKg().subtract(input.targetWeightKg())
                .divide(expectedWeekly, 0, RoundingMode.CEILING).longValueExact();

        LocalDate suggestedDate = input.calculationDate().plusWeeks(weeks);
        String safetyMessage;
        if (input.requestedTargetDate().isBefore(suggestedDate)) {
            safetyMessage = "目标日期早于安全估算日期，已按安全速度提供建议日期";
        } else if (input.adjustments() != null && input.adjustments().exerciseDays() != null
                && input.adjustments().exerciseDays() > input.currentExerciseDays() + 2) {
            safetyMessage = "运动天数增加较多，请循序渐进并根据身体状态调整";
        } else {
            safetyMessage = "计划数值为估算结果，请结合实际状态调整";
        }

        return new Result(
                RULE_VERSION,
                bmiRaw.setScale(1, RoundingMode.HALF_UP),
                bmrRaw.setScale(0, RoundingMode.HALF_UP).intValueExact(),
                tdeeRaw.setScale(0, RoundingMode.HALF_UP).intValueExact(),
                targetKcal,
                BigDecimal.valueOf(targetKcal).multiply(new BigDecimal("0.25"))
                        .divide(new BigDecimal("4"), 0, RoundingMode.HALF_UP).intValueExact(),
                BigDecimal.valueOf(targetKcal).multiply(new BigDecimal("0.50"))
                        .divide(new BigDecimal("4"), 0, RoundingMode.HALF_UP).intValueExact(),
                BigDecimal.valueOf(targetKcal).multiply(new BigDecimal("0.25"))
                        .divide(new BigDecimal("9"), 0, RoundingMode.HALF_UP).intValueExact(),
                waterMl, exerciseDays, exerciseMinutes, sleepHours,
                expectedWeekly.setScale(2, RoundingMode.HALF_UP),
                suggestedDate,
                safetyMessage
        );
    }

    private BigDecimal activityFactor(String level) {
        return switch (level) {
            case "LOW" -> new BigDecimal("1.20");
            case "LIGHT" -> new BigDecimal("1.375");
            case "MODERATE" -> new BigDecimal("1.55");
            case "HIGH" -> new BigDecimal("1.725");
            default -> throw new IllegalArgumentException("不支持的活动水平");
        };
    }

    private BigDecimal max(BigDecimal... values) {
        BigDecimal result = values[0];
        for (BigDecimal value : values) {
            result = result.max(value);
        }
        return result;
    }

    private int roundTo(BigDecimal value, int step) {
        return value.divide(BigDecimal.valueOf(step), 0, RoundingMode.HALF_UP).intValueExact() * step;
    }

    private BigDecimal clamp(BigDecimal value, String minimum, String maximum) {
        return value.max(new BigDecimal(minimum)).min(new BigDecimal(maximum));
    }

    private BigDecimal nearestHalf(BigDecimal value) {
        return value.multiply(new BigDecimal("2")).setScale(0, RoundingMode.HALF_UP)
                .divide(new BigDecimal("2"), 1, RoundingMode.UNNECESSARY);
    }

    public record Input(
            int age,
            String metabolicBasis,
            BigDecimal heightCm,
            BigDecimal weightKg,
            String activityLevel,
            BigDecimal targetWeightKg,
            LocalDate requestedTargetDate,
            BigDecimal currentSleepHours,
            int currentExerciseDays,
            LocalDate calculationDate,
            Adjustments adjustments
    ) {
    }

    public record Adjustments(
            Integer targetKcal,
            Integer waterMl,
            Integer exerciseDays,
            Integer exerciseMinutes,
            BigDecimal sleepHours
    ) {
    }

    public record Result(
            String ruleVersion,
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
    }
}
