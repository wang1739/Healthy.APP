package com.lightbite.healthy.nutrition;

import com.lightbite.healthy.common.api.ApiException;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class FoodService {

    private static final Set<String> SCOPES = Set.of("ALL", "SYSTEM", "MINE");
    private static final Set<String> CATEGORIES = Set.of(
            "STAPLE", "MEAT", "PROTEIN", "DAIRY", "VEGETABLE", "FRUIT", "SNACK", "CUSTOM");
    private final JdbcTemplate jdbc;

    public FoodService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<NutritionDtos.FoodResponse> search(
            String userId, String query, String scope, int limit
    ) {
        String effectiveScope = scope == null || scope.isBlank() ? "ALL" : scope.toUpperCase();
        if (!SCOPES.contains(effectiveScope)) {
            throw invalid("INVALID_SCOPE", "食物范围不受支持");
        }
        validateLimit(limit);
        String ownerClause = switch (effectiveScope) {
            case "SYSTEM" -> "owner_user_id IS NULL";
            case "MINE" -> "owner_user_id = ?";
            default -> "(owner_user_id IS NULL OR owner_user_id = ?)";
        };
        String term = "%" + (query == null ? "" : query.trim()) + "%";
        List<Object> parameters = new ArrayList<>();
        if (!"SYSTEM".equals(effectiveScope)) {
            parameters.add(userId);
        }
        parameters.add(term);
        parameters.add(limit);
        return jdbc.query("""
                SELECT * FROM foods
                WHERE deleted_at IS NULL AND %s AND name LIKE ?
                ORDER BY CASE WHEN owner_user_id IS NULL THEN 1 ELSE 0 END, name, id
                LIMIT ?
                """.formatted(ownerClause), (rs, rowNum) -> foodRow(rs), parameters.toArray())
                .stream().map(this::food).toList();
    }

    public NutritionDtos.FoodSuggestionsResponse suggestions(String userId, int limit) {
        validateLimit(limit);
        List<String> recentIds = jdbc.queryForList("""
                SELECT food_id FROM meal_entries
                WHERE user_id=? AND deleted_at IS NULL AND food_id IS NOT NULL
                ORDER BY created_at DESC, id DESC
                """, String.class, userId);
        Map<String, Boolean> unique = new LinkedHashMap<>();
        recentIds.forEach(id -> unique.putIfAbsent(id, Boolean.TRUE));
        List<NutritionDtos.FoodResponse> recent = visibleFoods(userId, unique.keySet().stream().limit(limit).toList());

        List<String> frequentIds = jdbc.queryForList("""
                SELECT food_id FROM meal_entries
                WHERE user_id=? AND deleted_at IS NULL AND food_id IS NOT NULL
                GROUP BY food_id
                ORDER BY COUNT(*) DESC, MAX(created_at) DESC, food_id
                LIMIT ?
                """, String.class, userId, limit);
        return new NutritionDtos.FoodSuggestionsResponse(recent, visibleFoods(userId, frequentIds));
    }

    @Transactional
    public NutritionDtos.FoodResponse createCustom(String userId, NutritionDtos.CustomFoodRequest request) {
        if (request == null || request.name() == null || request.name().trim().isEmpty()) {
            throw invalid("INVALID_FOOD_NAME", "请输入食物名称");
        }
        String name = request.name().trim();
        if (name.length() > 30) {
            throw invalid("INVALID_FOOD_NAME", "食物名称最多 30 个字符");
        }
        BigDecimal base = positive(request.baseGrams(), "请输入正确的基准克数", new BigDecimal("5000"));
        BigDecimal calories = per100(request.calories(), base, new BigDecimal("900"), "热量");
        BigDecimal protein = per100(request.protein(), base, new BigDecimal("100"), "蛋白质");
        BigDecimal carbs = per100(request.carbs(), base, new BigDecimal("100"), "碳水");
        BigDecimal fat = per100(request.fat(), base, new BigDecimal("100"), "脂肪");
        String category = request.category() == null || request.category().isBlank()
                ? "CUSTOM" : request.category().trim().toUpperCase();
        if (!CATEGORIES.contains(category)) {
            throw invalid("INVALID_CATEGORY", "食物分类不受支持");
        }
        String id = UUID.randomUUID().toString();
        try {
            jdbc.update("""
                    INSERT INTO foods
                    (id,owner_user_id,name,category,calories_per_100g,protein_per_100g,carbs_per_100g,fat_per_100g)
                    VALUES (?,?,?,?,?,?,?,?)
                    """, id, userId, name,
                    category, calories, protein, carbs, fat);
        } catch (DataIntegrityViolationException exception) {
            throw new ApiException(HttpStatus.CONFLICT, "FOOD_NAME_EXISTS", "我的食物中已存在同名食物");
        }
        return findVisible(userId, id);
    }

    NutritionDtos.FoodResponse findVisible(String userId, String foodId) {
        List<FoodRow> foods = jdbc.query("""
                SELECT * FROM foods
                WHERE id=? AND deleted_at IS NULL AND (owner_user_id IS NULL OR owner_user_id=?)
                """, (rs, rowNum) -> foodRow(rs), foodId, userId);
        if (foods.isEmpty()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "FOOD_NOT_FOUND", "食物不存在或不可用");
        }
        return food(foods.get(0));
    }

    private List<NutritionDtos.FoodResponse> visibleFoods(String userId, List<String> ids) {
        List<NutritionDtos.FoodResponse> result = new ArrayList<>();
        for (String id : ids) {
            try {
                result.add(findVisible(userId, id));
            } catch (ApiException ignored) {
                // A deleted custom food is intentionally omitted from suggestions.
            }
        }
        return result;
    }

    private FoodRow foodRow(ResultSet rs) throws SQLException {
        return new FoodRow(rs.getString("id"), rs.getString("name"), rs.getString("category"),
                rs.getBigDecimal("calories_per_100g"), rs.getBigDecimal("protein_per_100g"),
                rs.getBigDecimal("carbs_per_100g"), rs.getBigDecimal("fat_per_100g"),
                rs.getString("owner_user_id") != null);
    }

    private NutritionDtos.FoodResponse food(FoodRow food) {
        List<NutritionDtos.PortionResponse> portions = jdbc.query("""
                SELECT id,label,grams FROM food_portions
                WHERE food_id=? ORDER BY sort_order,id
                """, (portion, rowNum) -> new NutritionDtos.PortionResponse(
                        portion.getString("id"), portion.getString("label"), portion.getBigDecimal("grams")), food.id());
        return new NutritionDtos.FoodResponse(
                food.id(), food.name(), food.category(), food.calories(), food.protein(),
                food.carbs(), food.fat(), food.custom(), portions);
    }

    private BigDecimal per100(BigDecimal value, BigDecimal base, BigDecimal maximum, String label) {
        if (value == null || value.signum() < 0) {
            throw invalid("INVALID_NUTRITION", label + "不能为负数");
        }
        BigDecimal normalized = value.multiply(BigDecimal.valueOf(100)).divide(base, 4, RoundingMode.HALF_UP);
        if (normalized.compareTo(maximum) > 0) {
            throw invalid("INVALID_NUTRITION", label + "数值过大");
        }
        return normalized;
    }

    private BigDecimal positive(BigDecimal value, String message, BigDecimal maximum) {
        if (value == null || value.signum() <= 0 || value.compareTo(maximum) > 0) {
            throw invalid("INVALID_GRAMS", message);
        }
        return value;
    }

    private void validateLimit(int limit) {
        if (limit < 1) {
            throw invalid("INVALID_LIMIT", "查询数量至少为 1");
        }
        if (limit > 50) {
            throw invalid("INVALID_LIMIT", "每次最多查询 50 种食物");
        }
    }

    private ApiException invalid(String code, String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, code, message);
    }

    private record FoodRow(
            String id, String name, String category, BigDecimal calories, BigDecimal protein,
            BigDecimal carbs, BigDecimal fat, boolean custom
    ) {
    }
}
