package com.lightbite.healthy.nutrition;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.util.List;
import org.junit.jupiter.api.Test;

class NutritionCalculatorTests {

    private final NutritionCalculator calculator = new NutritionCalculator();

    @Test
    void calculatesFromPerHundredGramsWithoutBinaryFloatingPoint() {
        var result = calculator.calculate(new BigDecimal("116"), new BigDecimal("2.6"),
                new BigDecimal("25.9"), new BigDecimal("0.3"), new BigDecimal("150"));

        assertThat(result.calories()).isEqualByComparingTo("174");
        assertThat(result.protein()).isEqualByComparingTo("3.9");
        assertThat(result.carbs()).isEqualByComparingTo("38.85");
        assertThat(result.fat()).isEqualByComparingTo("0.45");
    }

    @Test
    void sumsPreciseValuesBeforeDisplayRounding() {
        var one = new NutritionDtos.Nutrients(new BigDecimal("0.49"), new BigDecimal("0.06"),
                BigDecimal.ZERO, BigDecimal.ZERO);
        var total = calculator.sum(List.of(one, one));

        assertThat(calculator.display(total).calories()).isEqualByComparingTo("1");
        assertThat(calculator.display(total).protein()).isEqualByComparingTo("0.1");
    }

    @Test
    void keepsZeroNutritionAtZero() {
        assertThat(calculator.calculate(BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO,
                BigDecimal.ZERO, new BigDecimal("5000")))
                .isEqualTo(new NutritionDtos.Nutrients(BigDecimal.ZERO, BigDecimal.ZERO,
                        BigDecimal.ZERO, BigDecimal.ZERO));
    }
}
