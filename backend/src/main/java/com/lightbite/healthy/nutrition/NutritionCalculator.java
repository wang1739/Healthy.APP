package com.lightbite.healthy.nutrition;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.List;
import org.springframework.stereotype.Component;

@Component
public class NutritionCalculator {

    public NutritionDtos.Nutrients calculate(
            BigDecimal caloriesPer100g,
            BigDecimal proteinPer100g,
            BigDecimal carbsPer100g,
            BigDecimal fatPer100g,
            BigDecimal grams
    ) {
        if (caloriesPer100g.signum() == 0 && proteinPer100g.signum() == 0
                && carbsPer100g.signum() == 0 && fatPer100g.signum() == 0) {
            return zero();
        }
        return new NutritionDtos.Nutrients(scale(caloriesPer100g, grams), scale(proteinPer100g, grams),
                scale(carbsPer100g, grams), scale(fatPer100g, grams));
    }

    public NutritionDtos.Nutrients sum(List<NutritionDtos.Nutrients> values) {
        BigDecimal calories = BigDecimal.ZERO;
        BigDecimal protein = BigDecimal.ZERO;
        BigDecimal carbs = BigDecimal.ZERO;
        BigDecimal fat = BigDecimal.ZERO;
        for (NutritionDtos.Nutrients value : values) {
            calories = calories.add(value.calories());
            protein = protein.add(value.protein());
            carbs = carbs.add(value.carbs());
            fat = fat.add(value.fat());
        }
        return new NutritionDtos.Nutrients(calories, protein, carbs, fat);
    }

    public NutritionDtos.Nutrients display(NutritionDtos.Nutrients value) {
        return new NutritionDtos.Nutrients(
                value.calories().setScale(0, RoundingMode.HALF_UP),
                value.protein().setScale(1, RoundingMode.HALF_UP),
                value.carbs().setScale(1, RoundingMode.HALF_UP),
                value.fat().setScale(1, RoundingMode.HALF_UP));
    }

    private BigDecimal scale(BigDecimal per100g, BigDecimal grams) {
        return per100g.multiply(grams).divide(BigDecimal.valueOf(100), 8, RoundingMode.HALF_UP)
                .stripTrailingZeros();
    }

    private NutritionDtos.Nutrients zero() {
        return new NutritionDtos.Nutrients(BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO);
    }
}
