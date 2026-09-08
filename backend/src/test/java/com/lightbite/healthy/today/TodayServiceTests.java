package com.lightbite.healthy.today;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;

import com.lightbite.healthy.plan.PlanDtos;
import com.lightbite.healthy.plan.PlanService;
import com.lightbite.healthy.hydration.HydrationDtos;
import com.lightbite.healthy.hydration.HydrationService;
import com.lightbite.healthy.nutrition.NutritionDtos;
import com.lightbite.healthy.nutrition.NutritionService;
import com.lightbite.healthy.profile.ProfileDtos;
import com.lightbite.healthy.profile.ProfileService;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class TodayServiceTests {

    private static final String USER_ID = "today-user";
    private final PlanService plans = mock(PlanService.class);
    private final ProfileService profiles = mock(ProfileService.class);
    private final NutritionService nutrition = mock(NutritionService.class);
    private final HydrationService hydration = mock(HydrationService.class);
    private TodayService service;

    @BeforeEach
    void setUp() {
        service = new TodayService(plans, profiles, nutrition, hydration);
        when(profiles.completeness(USER_ID)).thenReturn(completeness(true, false));
        when(profiles.measurements(USER_ID)).thenReturn(List.of());
        when(plans.current(USER_ID)).thenReturn(current("EMPTY", null));
        when(nutrition.day(USER_ID, LocalDate.of(2026, 9, 8))).thenReturn(day("EMPTY", null));
        when(nutrition.day(USER_ID, LocalDate.now())).thenReturn(day("EMPTY", null));
        when(hydration.day(eq(USER_ID), any(LocalDate.class), anyString())).thenReturn(hydrationDay("EMPTY", 0));
    }

    @Test
    void mapsActivePlanAndLatestWeightWithoutRecalculatingTargets() {
        Instant measuredAt = Instant.parse("2026-09-07T08:30:00Z");
        when(plans.current(USER_ID)).thenReturn(current("ACTIVE", result()));
        when(profiles.measurements(USER_ID)).thenReturn(List.of(
                new ProfileDtos.MeasurementResponse("latest", new BigDecimal("62.5"), null, null, measuredAt),
                new ProfileDtos.MeasurementResponse("older", new BigDecimal("63.0"), null, null, measuredAt.minusSeconds(60))));

        TodayDtos.TodayResponse response = service.get(USER_ID, LocalDate.of(2026, 9, 8));

        assertThat(response.plan().status()).isEqualTo(TodayDtos.ModuleStatus.READY);
        assertThat(response.plan().state()).isEqualTo("ACTIVE");
        assertThat(response.plan().targetKcal()).isEqualTo(1470);
        assertThat(response.plan().proteinG()).isEqualTo(110);
        assertThat(response.plan().waterMl()).isEqualTo(1900);
        assertThat(response.weight().valueKg()).isEqualByComparingTo("62.5");
        assertThat(response.weight().measuredAt()).isEqualTo(measuredAt);
        assertThat(response.nextAction().type()).isEqualTo("VIEW_PLAN");
    }

    @Test
    void returnsIndependentErrorsWhenOneSourceFails() {
        when(plans.current(USER_ID)).thenThrow(new IllegalStateException("database detail"));
        when(profiles.measurements(USER_ID)).thenReturn(List.of(
                new ProfileDtos.MeasurementResponse("weight", new BigDecimal("61.2"), null, null, Instant.now())));

        TodayDtos.TodayResponse response = service.get(USER_ID, LocalDate.now());

        assertThat(response.plan().status()).isEqualTo(TodayDtos.ModuleStatus.ERROR);
        assertThat(response.plan().message()).doesNotContain("database detail");
        assertThat(response.weight().status()).isEqualTo(TodayDtos.ModuleStatus.READY);
    }

    @Test
    void keepsPlanWhenWeightSourceFails() {
        when(plans.current(USER_ID)).thenReturn(current("ACTIVE", result()));
        when(profiles.measurements(USER_ID)).thenThrow(new IllegalStateException("measurement detail"));

        TodayDtos.TodayResponse response = service.get(USER_ID, LocalDate.now());

        assertThat(response.plan().status()).isEqualTo(TodayDtos.ModuleStatus.READY);
        assertThat(response.weight().status()).isEqualTo(TodayDtos.ModuleStatus.ERROR);
        assertThat(response.weight().message()).doesNotContain("measurement detail");
    }

    @Test
    void reportsBothModulesWhenBothSourcesFail() {
        when(plans.current(USER_ID)).thenThrow(new IllegalStateException("plan"));
        when(profiles.measurements(USER_ID)).thenThrow(new IllegalStateException("weight"));

        TodayDtos.TodayResponse response = service.get(USER_ID, LocalDate.now());

        assertThat(response.plan().status()).isEqualTo(TodayDtos.ModuleStatus.ERROR);
        assertThat(response.weight().status()).isEqualTo(TodayDtos.ModuleStatus.ERROR);
    }

    @Test
    void returnsEmptyNutritionAndHydrationWhileOtherFutureModulesStayComingSoon() {
        TodayDtos.TodayResponse response = service.get(USER_ID, LocalDate.now());

        assertThat(response.nutrition().status()).isEqualTo(TodayDtos.ModuleStatus.EMPTY);
        assertThat(response.hydration().status()).isEqualTo(TodayDtos.ModuleStatus.EMPTY);
        assertThat(response.activity().status()).isEqualTo(TodayDtos.ModuleStatus.COMING_SOON);
        assertThat(response.sleep().status()).isEqualTo(TodayDtos.ModuleStatus.COMING_SOON);
        assertThat(response.tasks().status()).isEqualTo(TodayDtos.ModuleStatus.COMING_SOON);
    }

    @Test
    void mapsReadyHydrationAndContainsItsFailure() {
        LocalDate date = LocalDate.of(2026, 9, 8);
        when(hydration.day(eq(USER_ID), eq(date), anyString())).thenReturn(hydrationDay("READY", 750));

        TodayDtos.TodayResponse ready = service.get(USER_ID, date);
        assertThat(ready.hydration().status()).isEqualTo(TodayDtos.ModuleStatus.READY);
        assertThat(ready.hydration().consumedMl()).isEqualTo(750);
        assertThat(ready.hydration().targetMl()).isEqualTo(2000);
        assertThat(ready.hydration().remainingMl()).isEqualTo(1250);
        assertThat(ready.hydration().progress()).isEqualByComparingTo("0.3750");

        when(hydration.day(eq(USER_ID), eq(date), anyString())).thenThrow(new IllegalStateException("sql detail"));
        TodayDtos.TodayResponse failed = service.get(USER_ID, date);
        assertThat(failed.hydration().status()).isEqualTo(TodayDtos.ModuleStatus.ERROR);
        assertThat(failed.hydration().message()).doesNotContain("sql detail");
        assertThat(failed.plan().status()).isEqualTo(TodayDtos.ModuleStatus.EMPTY);
        assertThat(failed.nutrition().status()).isEqualTo(TodayDtos.ModuleStatus.EMPTY);
    }

    @Test
    void hidesHydrationWhenProfileIsIncomplete() {
        when(profiles.completeness(USER_ID)).thenReturn(completeness(false, false));
        when(hydration.day(eq(USER_ID), any(LocalDate.class), anyString())).thenReturn(hydrationDay("READY", 750));

        TodayDtos.TodayResponse response = service.get(USER_ID, LocalDate.of(2026, 9, 8));

        assertThat(response.hydration().status()).isEqualTo(TodayDtos.ModuleStatus.PROFILE_INCOMPLETE);
        assertThat(response.hydration().consumedMl()).isNull();
        assertThat(response.hydration().targetMl()).isNull();
    }

    @Test
    void mapsReadyNutritionAndContainsItsFailure() {
        LocalDate date = LocalDate.of(2026, 9, 8);
        when(nutrition.day(USER_ID, date)).thenReturn(day("READY",
                new NutritionDtos.TargetResponse(1470, 110, 155, 45)));

        TodayDtos.TodayResponse ready = service.get(USER_ID, date);
        assertThat(ready.nutrition().status()).isEqualTo(TodayDtos.ModuleStatus.READY);
        assertThat(ready.nutrition().consumedKcal()).isEqualTo(321);
        assertThat(ready.nutrition().targetKcal()).isEqualTo(1470);
        assertThat(ready.nutrition().proteinG()).isEqualByComparingTo("20.5");

        when(nutrition.day(USER_ID, date)).thenThrow(new IllegalStateException("sql detail"));
        TodayDtos.TodayResponse failed = service.get(USER_ID, date);
        assertThat(failed.nutrition().status()).isEqualTo(TodayDtos.ModuleStatus.ERROR);
        assertThat(failed.nutrition().message()).doesNotContain("sql detail");
        assertThat(failed.plan().status()).isEqualTo(TodayDtos.ModuleStatus.EMPTY);
        assertThat(failed.weight().status()).isEqualTo(TodayDtos.ModuleStatus.EMPTY);
    }

    @Test
    void choosesNextActionFromProfileAndPlanState() {
        when(profiles.completeness(USER_ID)).thenReturn(completeness(false, false));
        when(plans.current(USER_ID)).thenReturn(current("ACTIVE", result()));
        TodayDtos.TodayResponse incomplete = service.get(USER_ID, LocalDate.now());
        assertThat(incomplete.nextAction().type()).isEqualTo("COMPLETE_PROFILE");
        assertThat(incomplete.plan().state()).isEqualTo("PROFILE_INCOMPLETE");
        assertThat(incomplete.plan().targetKcal()).isNull();

        when(profiles.completeness(USER_ID)).thenReturn(completeness(true, true));
        TodayDtos.TodayResponse blocked = service.get(USER_ID, LocalDate.now());
        assertThat(blocked.nextAction().type()).isEqualTo("VIEW_RISK_GUIDANCE");

        when(plans.current(USER_ID)).thenReturn(current("RISK_BLOCKED", null));
        blocked = service.get(USER_ID, LocalDate.now());
        assertThat(blocked.plan().targetKcal()).isNull();
        assertThat(blocked.nextAction().type()).isEqualTo("VIEW_RISK_GUIDANCE");

        when(profiles.completeness(USER_ID)).thenReturn(completeness(true, false));
        when(plans.current(USER_ID)).thenReturn(current("PAUSED", result()));
        assertThat(service.get(USER_ID, LocalDate.now()).nextAction().type()).isEqualTo("RESUME_PLAN");

        when(plans.current(USER_ID)).thenReturn(current("EMPTY", null));
        assertThat(service.get(USER_ID, LocalDate.now()).nextAction().type()).isEqualTo("CREATE_PLAN");
    }

    private ProfileDtos.CompletenessResponse completeness(boolean complete, boolean blocked) {
        return new ProfileDtos.CompletenessResponse(
                complete ? 7 : 2, complete ? 100 : 28, complete, blocked, false,
                false, "FEMALE", "FEMALE", LocalDate.of(1995, 6, 18));
    }

    private PlanDtos.CurrentResponse current(String state, PlanDtos.PlanResultResponse result) {
        return new PlanDtos.CurrentResponse(
                state, result == null ? null : "plan-1", result == null ? null : 1,
                result == null ? null : 1, null, null, null, false, result);
    }

    private PlanDtos.PlanResultResponse result() {
        return new PlanDtos.PlanResultResponse(
                "FAT_LOSS_V1", true, new BigDecimal("22.96"), 1320, 1815,
                1470, 110, 155, 45, 1900, 4, 35, new BigDecimal("8.0"),
                new BigDecimal("-0.3"), LocalDate.of(2027, 3, 1), "请根据身体感受调整");
    }

    private NutritionDtos.DayResponse day(String status, NutritionDtos.TargetResponse target) {
        return new NutritionDtos.DayResponse(LocalDate.of(2026, 9, 8), status, List.of(),
                new NutritionDtos.Nutrients(new BigDecimal("321"), new BigDecimal("20.5"),
                        new BigDecimal("30.4"), new BigDecimal("8.1")), target);
    }

    private HydrationDtos.DayResponse hydrationDay(String status, int total) {
        var settings = new HydrationDtos.SettingsResponse(null, 2000, 250, false,
                "08:00", "22:00", 120, null, null, "DEFAULT", null, null, false, 0);
        return new HydrationDtos.DayResponse(LocalDate.of(2026, 9, 8), status, List.of(), total,
                2000, Math.max(0, 2000 - total), new BigDecimal(total).divide(new BigDecimal("2000")),
                "DEFAULT", settings);
    }
}
