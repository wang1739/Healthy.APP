package com.lightbite.healthy.tasks;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.lightbite.healthy.activity.ActivityDtos;
import com.lightbite.healthy.activity.ActivityService;
import com.lightbite.healthy.hydration.HydrationDtos;
import com.lightbite.healthy.hydration.HydrationService;
import com.lightbite.healthy.nutrition.NutritionDtos;
import com.lightbite.healthy.nutrition.NutritionService;
import com.lightbite.healthy.plan.PlanDtos;
import com.lightbite.healthy.plan.PlanService;
import com.lightbite.healthy.sleep.SleepDtos;
import com.lightbite.healthy.sleep.SleepService;
import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;

class TaskHealthLinkServiceTests {
    private static final String USER = "health-task-user";
    private static final LocalDate DATE = LocalDate.of(2026, 9, 9);
    private final PlanService plans = mock(PlanService.class);
    private final NutritionService nutrition = mock(NutritionService.class);
    private final HydrationService hydration = mock(HydrationService.class);
    private final ActivityService activity = mock(ActivityService.class);
    private final SleepService sleep = mock(SleepService.class);
    private JdbcTemplate jdbc;
    private TaskHealthLinkService links;
    private TaskService tasks;

    @BeforeEach
    void setUp() {
        var dataSource = new SingleConnectionDataSource("jdbc:h2:mem:task_links_"
                + UUID.randomUUID().toString().replace("-", "")
                + ";MODE=MySQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1", "sa", "", true);
        Flyway.configure().dataSource(dataSource).load().migrate();
        jdbc = new JdbcTemplate(dataSource);
        jdbc.update("INSERT INTO users (id,phone,status) VALUES (?,?,'ACTIVE')", USER, "13000000921");
        jdbc.update("INSERT INTO health_profiles (user_id,current_step,completed) VALUES (?,7,TRUE)", USER);
        jdbc.update("INSERT INTO health_plans (id,user_id,status,phase_start_date,phase_end_date,current_version) "
                + "VALUES ('plan-1',?,'ACTIVE','2026-09-01','2026-12-31',1)", USER);
        when(plans.current(USER)).thenReturn(plan(1, "ACTIVE"));
        links = new TaskHealthLinkService(jdbc, new TaskSchedulePolicy(), plans, nutrition, hydration, activity, sleep);
        tasks = new TaskService(jdbc, new TaskSchedulePolicy(), links,
                Clock.fixed(Instant.parse("2026-09-09T00:00:00Z"), ZoneOffset.UTC));
    }

    @Test
    void createsStablePlanTemplatesWithDeterministicExerciseDistribution() {
        links.ensurePlanTemplates(USER, DATE, "Asia/Shanghai");
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM task_templates WHERE user_id=? AND source='PLAN'",
                Integer.class, USER)).isEqualTo(8);
        assertThat(jdbc.queryForList("SELECT task_code FROM task_templates WHERE user_id=? ORDER BY task_code",
                String.class, USER)).contains("MEAL_BREAKFAST", "MEAL_LUNCH", "MEAL_DINNER",
                "HYDRATION_TARGET", "SLEEP_RECORD", "ACTIVITY_SESSION_1", "ACTIVITY_SESSION_2",
                "ACTIVITY_SESSION_3");
        assertThat(jdbc.queryForList("SELECT weekdays_mask FROM task_templates WHERE task_code LIKE 'ACTIVITY_%' "
                + "ORDER BY task_code", Integer.class)).containsExactly(1, 4, 16);
        assertThat(jdbc.queryForList("SELECT health_link_target FROM task_templates "
                + "WHERE task_code LIKE 'ACTIVITY_%' ORDER BY task_code", Integer.class))
                .containsExactly(34, 33, 33);
        links.ensurePlanTemplates(USER, DATE, "Asia/Shanghai");
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM task_templates WHERE user_id=?",
                Integer.class, USER)).isEqualTo(8);
    }

    @Test
    void doesNotGenerateForUnavailablePlansAndDoesNotBackfillPastDays() {
        for (String state : List.of("EMPTY", "PAUSED", "NEEDS_RECALCULATION", "RISK_BLOCKED")) {
            when(plans.current(USER)).thenReturn(plan(1, state));
            links.ensurePlanTemplates(USER, DATE, "UTC");
            assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM task_templates", Integer.class)).isZero();
        }
        when(plans.current(USER)).thenReturn(plan(1, "ACTIVE"));
        stubEmptyHealth();
        tasks.day(USER, DATE, "UTC");
        when(plans.current(USER)).thenReturn(plan(1, "PAUSED"));
        tasks.day(USER, DATE.plusDays(1), "UTC");
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM task_instances WHERE original_local_date=?",
                Integer.class, DATE.plusDays(1))).isZero();
    }

    @Test
    void autoCompletesAndRollsBackFourHealthSourcesButPreservesUserState() {
        stubSatisfiedHealth();
        var day = tasks.day(USER, DATE, "UTC");
        assertThat(day.completed()).hasSize(6);
        assertThat(day.completed()).extracting(TaskDtos.InstanceResponse::completionSource)
                .containsOnly("AUTO_HEALTH_DATA");

        stubEmptyHealth();
        assertThat(tasks.day(USER, DATE, "UTC").completed()).isEmpty();
        String breakfast = jdbc.queryForObject("SELECT i.id FROM task_instances i JOIN task_templates t "
                + "ON t.id=i.template_id WHERE t.task_code='MEAL_BREAKFAST'", String.class);
        tasks.complete(USER, breakfast, "manual", "UTC");
        String lunch = jdbc.queryForObject("SELECT i.id FROM task_instances i JOIN task_templates t "
                + "ON t.id=i.template_id WHERE t.task_code='MEAL_LUNCH'", String.class);
        String dinner = jdbc.queryForObject("SELECT i.id FROM task_instances i JOIN task_templates t "
                + "ON t.id=i.template_id WHERE t.task_code='MEAL_DINNER'", String.class);
        tasks.skip(USER, lunch, "manual-skip", null, "UTC");
        tasks.postpone(USER, dinner, "manual-postpone", new TaskDtos.PostponeRequest("LATER", null, "UTC"));
        stubSatisfiedHealth();
        var preserved = tasks.day(USER, DATE, "UTC");
        assertThat(preserved.completed()).extracting(TaskDtos.InstanceResponse::id)
                .contains(breakfast);
        assertThat(preserved.skipped()).extracting(TaskDtos.InstanceResponse::id).contains(lunch);
        assertThat(jdbc.queryForObject("SELECT status FROM task_instances WHERE id=?", String.class, dinner))
                .isEqualTo("PENDING");
        assertThat(tasks.week(USER, DATE, "UTC").autoCompletedCount()).isGreaterThan(0);
    }

    @Test
    void preservesOverridesReportsPlanUpdateAndAdoptsNewDefaults() {
        links.ensurePlanTemplates(USER, DATE, "UTC");
        jdbc.update("UPDATE task_templates SET title='我的早餐',user_overridden=TRUE WHERE task_code='MEAL_BREAKFAST'");
        when(plans.current(USER)).thenReturn(plan(2, "ACTIVE"));
        assertThat(links.hasPlanUpdate(USER)).isTrue();
        links.ensurePlanTemplates(USER, DATE, "UTC");
        assertThat(jdbc.queryForObject("SELECT title FROM task_templates WHERE task_code='MEAL_BREAKFAST'",
                String.class)).isEqualTo("我的早餐");
        links.adoptPlanUpdates(USER, DATE, "UTC");
        assertThat(links.hasPlanUpdate(USER)).isFalse();
        assertThat(jdbc.queryForObject("SELECT title FROM task_templates WHERE task_code='MEAL_BREAKFAST'",
                String.class)).isEqualTo("记录早餐");
        assertThat(jdbc.queryForObject("SELECT plan_version FROM task_templates WHERE task_code='MEAL_BREAKFAST'",
                Integer.class)).isEqualTo(2);
    }

    @Test
    void disabledPlanTemplateIsNotRebuiltOnRead() {
        stubEmptyHealth();
        tasks.day(USER, DATE, "UTC");
        String template = jdbc.queryForObject("SELECT id FROM task_templates WHERE task_code='MEAL_BREAKFAST'",
                String.class);
        tasks.deleteTemplate(USER, template, DATE, "UTC");
        tasks.day(USER, DATE, "UTC");
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM task_templates WHERE task_code='MEAL_BREAKFAST'",
                Integer.class)).isEqualTo(1);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM task_instances WHERE template_id=? "
                + "AND original_local_date=? AND deleted_at IS NULL", Integer.class, template, DATE)).isZero();
    }

    private void stubSatisfiedHealth() {
        var entry = new NutritionDtos.EntryResponse("e", "BREAKFAST", null, "早餐", BigDecimal.ONE,
                BigDecimal.ONE, BigDecimal.ONE, BigDecimal.ONE, BigDecimal.ONE, Instant.now(), Instant.now());
        when(nutrition.day(USER, DATE)).thenReturn(new NutritionDtos.DayResponse(DATE, "READY", List.of(
                new NutritionDtos.MealResponse("BREAKFAST", List.of(entry), nutrients()),
                new NutritionDtos.MealResponse("LUNCH", List.of(entry), nutrients()),
                new NutritionDtos.MealResponse("DINNER", List.of(entry), nutrients())), nutrients(), null));
        when(hydration.day(USER, DATE, "UTC")).thenReturn(hydrationDay(2000));
        when(activity.day(USER, DATE, "UTC")).thenReturn(new ActivityDtos.DayResponse(DATE, "READY", List.of(),
                1, 40, 100, BigDecimal.valueOf(60), "v"));
        var night = new SleepDtos.RecordResponse("s", "NIGHT", Instant.now(), Instant.now(), "UTC", DATE,
                480, 4, "良好", List.of(), null, "MANUAL");
        when(sleep.day(USER, DATE, "UTC")).thenReturn(new SleepDtos.DayResponse(DATE, "READY", night, List.of(),
                List.of(night), 480, 0, 480, 0, "ACTIVE"));
    }

    private void stubEmptyHealth() {
        when(nutrition.day(USER, DATE)).thenReturn(new NutritionDtos.DayResponse(DATE, "EMPTY", List.of(),
                nutrients(), null));
        when(hydration.day(USER, DATE, "UTC")).thenReturn(hydrationDay(0));
        when(activity.day(USER, DATE, "UTC")).thenReturn(new ActivityDtos.DayResponse(DATE, "EMPTY", List.of(),
                0, 0, 0, BigDecimal.valueOf(60), "v"));
        when(sleep.day(USER, DATE, "UTC")).thenReturn(new SleepDtos.DayResponse(DATE, "EMPTY", null, List.of(),
                List.of(), 0, 0, 480, null, "ACTIVE"));
    }

    private NutritionDtos.Nutrients nutrients() {
        return new NutritionDtos.Nutrients(BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO);
    }

    private HydrationDtos.DayResponse hydrationDay(int total) {
        var settings = new HydrationDtos.SettingsResponse(null, 2000, 250, false, "08:00", "22:00", 120,
                null, null, "DEFAULT", null, null, false, 0);
        return new HydrationDtos.DayResponse(DATE, total == 0 ? "EMPTY" : "READY", List.of(), total, 2000,
                Math.max(0, 2000 - total), BigDecimal.valueOf(total).divide(BigDecimal.valueOf(2000)),
                "DEFAULT", settings);
    }

    private PlanDtos.CurrentResponse plan(int version, String state) {
        var target = new PlanDtos.PlanResultResponse("FAT_LOSS_V1", true, BigDecimal.valueOf(22), 1300, 1800,
                1500, 100, 150, 45, 2000, 3, 100, BigDecimal.valueOf(8), BigDecimal.valueOf(-.3),
                LocalDate.of(2027, 3, 1), "安全提示");
        return new PlanDtos.CurrentResponse(state, "plan-1", version, 1, LocalDate.of(2026, 9, 1),
                LocalDate.of(2026, 12, 31), null, false, "ACTIVE".equals(state) ? target : null);
    }
}
