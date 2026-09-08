package com.lightbite.healthy.nutrition;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.lightbite.healthy.common.api.ApiException;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.concurrent.Executors;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;

@SpringBootTest
@ActiveProfiles("test")
class NutritionServiceTests {

    @Autowired NutritionService service;
    @Autowired JdbcTemplate jdbc;

    @BeforeEach
    void setUp() {
        jdbc.update("DELETE FROM meal_entries");
        jdbc.update("DELETE FROM health_plan_versions");
        jdbc.update("DELETE FROM health_plans");
        createUser("nutrition-a", "13000000201", true);
        createUser("nutrition-b", "13000000202", true);
        createUser("nutrition-incomplete", "13000000203", false);
    }

    @Test
    void createsUpdatesAndSoftDeletesWithFourStableMeals() {
        LocalDate date = LocalDate.now();
        var created = service.create("nutrition-a", "create-1",
                request(date, "BREAKFAST", "sys-rice", null, new BigDecimal("150")));

        assertThat(created.meals()).extracting(NutritionDtos.MealResponse::mealType)
                .containsExactly("BREAKFAST", "LUNCH", "DINNER", "SNACK");
        assertThat(created.total().calories()).isEqualByComparingTo("174");
        String id = created.meals().get(0).entries().get(0).id();

        var updated = service.update("nutrition-a", id,
                request(date, "LUNCH", "sys-egg", null, new BigDecimal("50")));
        assertThat(updated.meals().get(0).entries()).isEmpty();
        assertThat(updated.meals().get(1).entries().get(0).foodName()).isEqualTo("鸡蛋");
        assertThat(updated.total().calories()).isEqualByComparingTo("72");

        var deleted = service.delete("nutrition-a", id);
        assertThat(deleted.status()).isEqualTo("EMPTY");
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM meal_entries WHERE id=? AND deleted_at IS NOT NULL",
                Integer.class, id)).isEqualTo(1);
    }

    @Test
    void keepsSnapshotsWhenFoodLibraryChangesAndSupportsTemporaryCustomFood() {
        LocalDate date = LocalDate.now();
        var first = service.create("nutrition-a", "snapshot-1",
                request(date, "DINNER", "sys-rice", null, new BigDecimal("100")));
        jdbc.update("UPDATE foods SET calories_per_100g=800 WHERE id='sys-rice'");

        assertThat(service.day("nutrition-a", date).total().calories()).isEqualByComparingTo("116");
        jdbc.update("UPDATE foods SET calories_per_100g=116 WHERE id='sys-rice'");

        var custom = service.create("nutrition-a", "custom-1", new NutritionDtos.EntryRequest(
                date, "SNACK", null, "自制点心", new BigDecimal("30"), new BigDecimal("60"),
                new BigDecimal("120"), new BigDecimal("3"), new BigDecimal("20"),
                new BigDecimal("4"), false));
        assertThat(custom.total().calories()).isEqualByComparingTo("176");
        assertThat(first.status()).isEqualTo("READY");
    }

    @Test
    void savesARequestedCustomFoodForLaterSearch() {
        LocalDate date = LocalDate.now();
        var response = service.create("nutrition-a", "saved-custom", new NutritionDtos.EntryRequest(
                date, "SNACK", null, "自制能量球", new BigDecimal("25"), new BigDecimal("50"),
                new BigDecimal("100"), new BigDecimal("5"), new BigDecimal("12"),
                new BigDecimal("4"), true));

        assertThat(response.meals().get(3).entries().get(0).foodId()).isNotBlank();
        assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM foods WHERE owner_user_id='nutrition-a' AND name='自制能量球'",
                Integer.class)).isEqualTo(1);
    }

    @Test
    void returnsActivePlanTargetsOnly() {
        LocalDate date = LocalDate.now();
        assertThat(service.day("nutrition-a", date).target()).isNull();
        insertPlan("nutrition-a", "ACTIVE");
        assertThat(service.day("nutrition-a", date).target().calories()).isEqualTo(1500);
        jdbc.update("UPDATE health_plans SET status='PAUSED' WHERE user_id='nutrition-a'");
        assertThat(service.day("nutrition-a", date).target()).isNull();
    }

    @Test
    void rejectsIncompleteProfilesFutureDatesAndCrossUserChanges() {
        LocalDate today = LocalDate.now();
        assertThatThrownBy(() -> service.create("nutrition-incomplete", "bad-profile",
                request(today, "LUNCH", "sys-rice", null, BigDecimal.TEN)))
                .isInstanceOf(ApiException.class).hasMessage("请先完成健康档案");
        assertThatThrownBy(() -> service.create("nutrition-a", "future",
                request(today.plusDays(1), "LUNCH", "sys-rice", null, BigDecimal.TEN)))
                .isInstanceOf(ApiException.class).hasMessage("未来日期不能记录饮食");
        assertThatThrownBy(() -> service.create("nutrition-a", "bad-meal",
                request(today, "BRUNCH", "sys-rice", null, BigDecimal.TEN)))
                .isInstanceOf(ApiException.class).hasMessage("餐次不受支持");
        assertThatThrownBy(() -> service.create("nutrition-a", "bad-grams",
                request(today, "LUNCH", "sys-rice", null, BigDecimal.ZERO)))
                .isInstanceOf(ApiException.class).hasMessage("克数必须大于 0 且不超过 5000");
        String id = service.create("nutrition-a", "owned",
                request(today, "LUNCH", "sys-rice", null, BigDecimal.TEN))
                .meals().get(1).entries().get(0).id();
        assertThatThrownBy(() -> service.delete("nutrition-b", id))
                .isInstanceOf(ApiException.class).hasMessage("餐食记录不存在");
    }

    @Test
    void serialAndConcurrentIdempotencyCreatesOnlyOneEntry() throws Exception {
        LocalDate date = LocalDate.now();
        var request = request(date, "LUNCH", "sys-rice", null, new BigDecimal("100"));
        service.create("nutrition-a", "same-key", request);
        service.create("nutrition-a", "same-key", request);

        var executor = Executors.newFixedThreadPool(2);
        try {
            var one = executor.submit(() -> service.create("nutrition-a", "race-key", request));
            var two = executor.submit(() -> service.create("nutrition-a", "race-key", request));
            one.get();
            two.get();
        } finally {
            executor.shutdownNow();
        }

        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM meal_entries WHERE user_id='nutrition-a'",
                Integer.class)).isEqualTo(2);
    }

    private NutritionDtos.EntryRequest request(
            LocalDate date, String mealType, String foodId, String name, BigDecimal grams
    ) {
        return new NutritionDtos.EntryRequest(date, mealType, foodId, name, grams,
                null, null, null, null, null, false);
    }

    private void createUser(String id, String phone, boolean complete) {
        jdbc.update("MERGE INTO users (id,phone,status) KEY(id) VALUES (?,?,'ACTIVE')", id, phone);
        jdbc.update("DELETE FROM health_profiles WHERE user_id=?", id);
        jdbc.update("INSERT INTO health_profiles (user_id,current_step,completed,risk_blocked) VALUES (?,?,?,FALSE)",
                id, complete ? 7 : 2, complete);
    }

    private void insertPlan(String userId, String status) {
        jdbc.update("INSERT INTO health_plans (id,user_id,status,phase_start_date,phase_end_date,current_version) "
                + "VALUES ('nutrition-plan',?,?,'2026-09-01','2026-09-28',1)", userId, status);
        jdbc.update("INSERT INTO health_plan_versions (id,plan_id,version_number,rule_version,profile_version,"
                + "calculation_date,age,metabolic_basis,height_cm,weight_kg,activity_level,target_weight_kg,"
                + "requested_target_date,bmi,bmr_kcal,tdee_kcal,target_kcal,protein_g,carbs_g,fat_g,water_ml,"
                + "exercise_days,exercise_minutes,sleep_hours,expected_weekly_change_kg,suggested_target_date,safety_message) "
                + "VALUES ('nutrition-version','nutrition-plan',1,'v1',1,'2026-09-01',30,'FEMALE',165,60,'LIGHT',55,"
                + "'2027-03-01',22,1300,1800,1500,100,160,45,1800,3,30,8,-.3,'2027-03-01','安全')");
    }
}
