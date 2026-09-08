package com.lightbite.healthy.nutrition;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

public final class NutritionDtos {

    private NutritionDtos() {
    }

    public record PortionResponse(String id, String label, BigDecimal grams) {
    }

    public record FoodResponse(
            String id,
            String name,
            String category,
            BigDecimal caloriesPer100g,
            BigDecimal proteinPer100g,
            BigDecimal carbsPer100g,
            BigDecimal fatPer100g,
            boolean custom,
            List<PortionResponse> portions
    ) {
    }

    public record CustomFoodRequest(
            String name,
            String category,
            BigDecimal baseGrams,
            BigDecimal calories,
            BigDecimal protein,
            BigDecimal carbs,
            BigDecimal fat
    ) {
    }

    public record FoodSuggestionsResponse(List<FoodResponse> recent, List<FoodResponse> frequent) {
    }

    public record Nutrients(BigDecimal calories, BigDecimal protein, BigDecimal carbs, BigDecimal fat) {
    }

    public record EntryRequest(
            LocalDate date,
            String mealType,
            String foodId,
            String foodName,
            BigDecimal grams,
            BigDecimal baseGrams,
            BigDecimal calories,
            BigDecimal protein,
            BigDecimal carbs,
            BigDecimal fat,
            Boolean saveCustomFood
    ) {
    }

    public record EntryResponse(
            String id,
            String mealType,
            String foodId,
            String foodName,
            BigDecimal grams,
            BigDecimal calories,
            BigDecimal protein,
            BigDecimal carbs,
            BigDecimal fat,
            Instant createdAt,
            Instant updatedAt
    ) {
    }

    public record MealResponse(
            String mealType,
            List<EntryResponse> entries,
            Nutrients subtotal
    ) {
    }

    public record TargetResponse(Integer calories, Integer protein, Integer carbs, Integer fat) {
    }

    public record DayResponse(
            LocalDate date,
            String status,
            List<MealResponse> meals,
            Nutrients total,
            TargetResponse target
    ) {
    }
}
