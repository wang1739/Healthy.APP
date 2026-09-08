package com.lightbite.healthy.nutrition;

import com.lightbite.healthy.common.api.ApiException;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
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
public class NutritionService {

    private static final List<String> MEAL_TYPES = List.of("BREAKFAST", "LUNCH", "DINNER", "SNACK");
    private static final Set<String> MEAL_TYPE_SET = Set.copyOf(MEAL_TYPES);
    private final JdbcTemplate jdbc;
    private final FoodService foods;
    private final NutritionCalculator calculator;

    public NutritionService(JdbcTemplate jdbc, FoodService foods, NutritionCalculator calculator) {
        this.jdbc = jdbc;
        this.foods = foods;
        this.calculator = calculator;
    }

    public NutritionDtos.DayResponse day(String userId, LocalDate date) {
        if (date == null) {
            throw invalid("INVALID_DATE", "请选择日期");
        }
        List<EntryValue> entries = jdbc.query("""
                SELECT * FROM meal_entries
                WHERE user_id=? AND entry_date=? AND deleted_at IS NULL
                ORDER BY CASE meal_type WHEN 'BREAKFAST' THEN 1 WHEN 'LUNCH' THEN 2
                         WHEN 'DINNER' THEN 3 ELSE 4 END, created_at, id
                """, (rs, rowNum) -> entry(rs), userId, date);

        List<NutritionDtos.MealResponse> meals = new ArrayList<>();
        List<NutritionDtos.Nutrients> all = new ArrayList<>();
        for (String mealType : MEAL_TYPES) {
            List<EntryValue> values = entries.stream().filter(entry -> mealType.equals(entry.mealType())).toList();
            List<NutritionDtos.EntryResponse> responses = values.stream().map(this::response).toList();
            List<NutritionDtos.Nutrients> nutrients = values.stream().map(EntryValue::nutrients).toList();
            all.addAll(nutrients);
            meals.add(new NutritionDtos.MealResponse(mealType, responses,
                    calculator.display(calculator.sum(nutrients))));
        }
        return new NutritionDtos.DayResponse(date, entries.isEmpty() ? "EMPTY" : "READY", meals,
                calculator.display(calculator.sum(all)), target(userId));
    }

    @Transactional
    public NutritionDtos.DayResponse create(
            String userId, String idempotencyKey, NutritionDtos.EntryRequest request
    ) {
        ensureCompleteProfile(userId);
        String key = validateKey(idempotencyKey);
        List<LocalDate> existingDates = jdbc.queryForList(
                "SELECT entry_date FROM meal_entries WHERE user_id=? AND idempotency_key=?",
                LocalDate.class, userId, key);
        if (!existingDates.isEmpty()) {
            return day(userId, existingDates.get(0));
        }
        ValidatedEntry value = validate(userId, request);
        Instant now = Instant.now();
        try {
            jdbc.update("""
                    INSERT INTO meal_entries
                    (id,user_id,entry_date,meal_type,food_id,food_name_snapshot,grams,
                     calories_snapshot,protein_snapshot,carbs_snapshot,fat_snapshot,idempotency_key,created_at,updated_at)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                    """, UUID.randomUUID().toString(), userId, value.date(), value.mealType(), value.foodId(),
                    value.foodName(), value.grams(), value.nutrients().calories(), value.nutrients().protein(),
                    value.nutrients().carbs(), value.nutrients().fat(), key, Timestamp.from(now), Timestamp.from(now));
        } catch (DataIntegrityViolationException exception) {
            LocalDate originalDate = jdbc.queryForObject(
                    "SELECT entry_date FROM meal_entries WHERE user_id=? AND idempotency_key=?",
                    LocalDate.class, userId, key);
            return day(userId, originalDate);
        }
        return day(userId, value.date());
    }

    @Transactional
    public NutritionDtos.DayResponse update(String userId, String entryId, NutritionDtos.EntryRequest request) {
        ensureCompleteProfile(userId);
        requireEntry(userId, entryId);
        ValidatedEntry value = validate(userId, request);
        jdbc.update("""
                UPDATE meal_entries SET entry_date=?,meal_type=?,food_id=?,food_name_snapshot=?,grams=?,
                  calories_snapshot=?,protein_snapshot=?,carbs_snapshot=?,fat_snapshot=?,updated_at=?
                WHERE id=? AND user_id=? AND deleted_at IS NULL
                """, value.date(), value.mealType(), value.foodId(), value.foodName(), value.grams(),
                value.nutrients().calories(), value.nutrients().protein(), value.nutrients().carbs(),
                value.nutrients().fat(), Timestamp.from(Instant.now()), entryId, userId);
        return day(userId, value.date());
    }

    @Transactional
    public NutritionDtos.DayResponse delete(String userId, String entryId) {
        ensureCompleteProfile(userId);
        Map<String, Object> entry = requireEntry(userId, entryId);
        LocalDate date = toDate(entry.get("entry_date"));
        rejectFuture(date);
        jdbc.update("UPDATE meal_entries SET deleted_at=?,updated_at=? WHERE id=? AND user_id=? AND deleted_at IS NULL",
                Timestamp.from(Instant.now()), Timestamp.from(Instant.now()), entryId, userId);
        return day(userId, date);
    }

    private ValidatedEntry validate(String userId, NutritionDtos.EntryRequest request) {
        if (request == null) {
            throw invalid("INVALID_ENTRY", "请填写餐食信息");
        }
        rejectFuture(request.date());
        if (!MEAL_TYPE_SET.contains(request.mealType())) {
            throw invalid("INVALID_MEAL_TYPE", "餐次不受支持");
        }
        BigDecimal grams = positive(request.grams(), new BigDecimal("5000"), "克数必须大于 0 且不超过 5000");
        if (request.foodId() != null && !request.foodId().isBlank()) {
            NutritionDtos.FoodResponse food = foods.findVisible(userId, request.foodId());
            return new ValidatedEntry(request.date(), request.mealType(), food.id(), food.name(), grams,
                    calculator.calculate(food.caloriesPer100g(), food.proteinPer100g(),
                            food.carbsPer100g(), food.fatPer100g(), grams));
        }
        String name = request.foodName() == null ? "" : request.foodName().trim();
        if (name.isEmpty() || name.length() > 30) {
            throw invalid("INVALID_FOOD_NAME", name.isEmpty() ? "请输入食物名称" : "食物名称最多 30 个字符");
        }
        BigDecimal base = positive(request.baseGrams(), new BigDecimal("5000"), "请输入正确的基准克数");
        BigDecimal calories = normalize(request.calories(), base, new BigDecimal("900"), "热量");
        BigDecimal protein = normalize(request.protein(), base, new BigDecimal("100"), "蛋白质");
        BigDecimal carbs = normalize(request.carbs(), base, new BigDecimal("100"), "碳水");
        BigDecimal fat = normalize(request.fat(), base, new BigDecimal("100"), "脂肪");
        String foodId = null;
        if (Boolean.TRUE.equals(request.saveCustomFood())) {
            NutritionDtos.FoodResponse saved = foods.createCustom(userId, new NutritionDtos.CustomFoodRequest(
                    name, "CUSTOM", base, request.calories(), request.protein(), request.carbs(), request.fat()));
            foodId = saved.id();
        }
        return new ValidatedEntry(request.date(), request.mealType(), foodId, name, grams,
                calculator.calculate(calories, protein, carbs, fat, grams));
    }

    private NutritionDtos.TargetResponse target(String userId) {
        List<NutritionDtos.TargetResponse> targets = jdbc.query("""
                SELECT v.target_kcal,v.protein_g,v.carbs_g,v.fat_g
                FROM health_plans p
                JOIN health_plan_versions v ON v.plan_id=p.id AND v.version_number=p.current_version
                JOIN health_profiles hp ON hp.user_id=p.user_id
                WHERE p.user_id=? AND p.status='ACTIVE' AND hp.completed=TRUE AND hp.risk_blocked=FALSE
                """, (rs, rowNum) -> new NutritionDtos.TargetResponse(rs.getInt("target_kcal"),
                        rs.getInt("protein_g"), rs.getInt("carbs_g"), rs.getInt("fat_g")), userId);
        return targets.isEmpty() ? null : targets.get(0);
    }

    private void ensureCompleteProfile(String userId) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM health_profiles WHERE user_id=? AND completed=TRUE",
                Integer.class, userId);
        if (count == null || count == 0) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "PROFILE_INCOMPLETE", "请先完成健康档案");
        }
    }

    private Map<String, Object> requireEntry(String userId, String entryId) {
        List<Map<String, Object>> entries = jdbc.queryForList(
                "SELECT id,entry_date FROM meal_entries WHERE id=? AND user_id=? AND deleted_at IS NULL",
                entryId, userId);
        if (entries.isEmpty()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "MEAL_ENTRY_NOT_FOUND", "餐食记录不存在");
        }
        return entries.get(0);
    }

    private EntryValue entry(ResultSet rs) throws SQLException {
        return new EntryValue(rs.getString("id"), rs.getString("meal_type"), rs.getString("food_id"),
                rs.getString("food_name_snapshot"), rs.getBigDecimal("grams"),
                new NutritionDtos.Nutrients(rs.getBigDecimal("calories_snapshot"),
                        rs.getBigDecimal("protein_snapshot"), rs.getBigDecimal("carbs_snapshot"),
                        rs.getBigDecimal("fat_snapshot")), rs.getTimestamp("created_at").toInstant(),
                rs.getTimestamp("updated_at").toInstant());
    }

    private NutritionDtos.EntryResponse response(EntryValue entry) {
        NutritionDtos.Nutrients shown = calculator.display(entry.nutrients());
        return new NutritionDtos.EntryResponse(entry.id(), entry.mealType(), entry.foodId(), entry.foodName(),
                entry.grams(), shown.calories(), shown.protein(), shown.carbs(), shown.fat(),
                entry.createdAt(), entry.updatedAt());
    }

    private String validateKey(String key) {
        if (key == null || key.trim().isEmpty()) {
            throw invalid("IDEMPOTENCY_KEY_REQUIRED", "新增餐食需要 Idempotency-Key");
        }
        if (key.trim().length() > 100) {
            throw invalid("INVALID_IDEMPOTENCY_KEY", "Idempotency-Key 最多 100 个字符");
        }
        return key.trim();
    }

    private void rejectFuture(LocalDate date) {
        if (date == null) {
            throw invalid("INVALID_DATE", "请选择日期");
        }
        if (date.isAfter(LocalDate.now())) {
            throw invalid("FUTURE_DATE_NOT_ALLOWED", "未来日期不能记录饮食");
        }
    }

    private BigDecimal positive(BigDecimal value, BigDecimal maximum, String message) {
        if (value == null || value.signum() <= 0 || value.compareTo(maximum) > 0) {
            throw invalid("INVALID_GRAMS", message);
        }
        return value;
    }

    private BigDecimal normalize(BigDecimal value, BigDecimal base, BigDecimal max, String label) {
        if (value == null || value.signum() < 0) {
            throw invalid("INVALID_NUTRITION", label + "不能为负数");
        }
        BigDecimal normalized = value.multiply(BigDecimal.valueOf(100)).divide(base, 4, RoundingMode.HALF_UP);
        if (normalized.compareTo(max) > 0) {
            throw invalid("INVALID_NUTRITION", label + "数值过大");
        }
        return normalized;
    }

    private LocalDate toDate(Object value) {
        return value instanceof LocalDate date ? date : ((java.sql.Date) value).toLocalDate();
    }

    private ApiException invalid(String code, String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, code, message);
    }

    private record ValidatedEntry(
            LocalDate date, String mealType, String foodId, String foodName,
            BigDecimal grams, NutritionDtos.Nutrients nutrients
    ) {
    }

    private record EntryValue(
            String id, String mealType, String foodId, String foodName, BigDecimal grams,
            NutritionDtos.Nutrients nutrients, Instant createdAt, Instant updatedAt
    ) {
    }
}
