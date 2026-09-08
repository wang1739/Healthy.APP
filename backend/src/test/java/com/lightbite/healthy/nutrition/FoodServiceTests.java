package com.lightbite.healthy.nutrition;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.lightbite.healthy.common.api.ApiException;
import java.math.BigDecimal;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;

@SpringBootTest
@ActiveProfiles("test")
class FoodServiceTests {

    @Autowired FoodService service;
    @Autowired JdbcTemplate jdbc;

    @BeforeEach
    void setUp() {
        jdbc.update("DELETE FROM meal_entries");
        jdbc.update("DELETE FROM food_portions WHERE food_id IN (SELECT id FROM foods WHERE owner_user_id IS NOT NULL)");
        jdbc.update("DELETE FROM foods WHERE owner_user_id IS NOT NULL");
        jdbc.update("MERGE INTO users (id,phone,status) KEY(id) VALUES ('food-a','13000000101','ACTIVE')");
        jdbc.update("MERGE INTO users (id,phone,status) KEY(id) VALUES ('food-b','13000000102','ACTIVE')");
    }

    @Test
    void searchesSystemFoodsAndKeepsPortionsOrdered() {
        var foods = service.search("food-a", "米", "SYSTEM", 20);

        assertThat(foods).extracting(NutritionDtos.FoodResponse::name).contains("米饭");
        assertThat(foods.stream().filter(food -> food.name().equals("米饭")).findFirst().orElseThrow().portions())
                .extracting(NutritionDtos.PortionResponse::label).containsExactly("1 碗");
    }

    @Test
    void isolatesMineAndNormalizesCustomNutritionFromBaseGrams() {
        var created = service.createCustom("food-a", new NutritionDtos.CustomFoodRequest(
                "家常肉饼", "CUSTOM", new BigDecimal("50"), new BigDecimal("120"),
                new BigDecimal("10"), new BigDecimal("5"), new BigDecimal("6")));

        assertThat(created.caloriesPer100g()).isEqualByComparingTo("240");
        assertThat(service.search("food-a", "肉饼", "MINE", 20)).hasSize(1);
        assertThat(service.search("food-b", "肉饼", "ALL", 20)).isEmpty();
        assertThatThrownBy(() -> service.createCustom("food-a", new NutritionDtos.CustomFoodRequest(
                "家常肉饼", "CUSTOM", new BigDecimal("50"), new BigDecimal("120"),
                new BigDecimal("10"), new BigDecimal("5"), new BigDecimal("6"))))
                .isInstanceOf(ApiException.class).hasMessage("我的食物中已存在同名食物");
    }

    @Test
    void rejectsInvalidScopeLimitAndNutrition() {
        assertThatThrownBy(() -> service.search("food-a", "", "OTHER", 20))
                .isInstanceOf(ApiException.class).hasMessage("食物范围不受支持");
        assertThatThrownBy(() -> service.search("food-a", "", "ALL", 51))
                .isInstanceOf(ApiException.class).hasMessage("每次最多查询 50 种食物");
        assertThatThrownBy(() -> service.createCustom("food-a", new NutritionDtos.CustomFoodRequest(
                " ", "CUSTOM", BigDecimal.TEN, BigDecimal.ONE, BigDecimal.ZERO,
                BigDecimal.ZERO, BigDecimal.ZERO)))
                .isInstanceOf(ApiException.class).hasMessage("请输入食物名称");
    }
}
