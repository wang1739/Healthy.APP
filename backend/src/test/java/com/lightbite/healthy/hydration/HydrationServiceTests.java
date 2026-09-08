package com.lightbite.healthy.hydration;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.lightbite.healthy.common.api.ApiException;
import com.lightbite.healthy.plan.PlanDtos;
import com.lightbite.healthy.plan.PlanService;
import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;

class HydrationServiceTests {

    private static final String USER_ID = "hydration-user";
    private static final Instant NOW = Instant.parse("2026-09-08T12:00:00Z");
    private final PlanService plans = mock(PlanService.class);
    private JdbcTemplate jdbc;
    private HydrationService service;

    @BeforeEach
    void setUp() {
        String url = "jdbc:h2:mem:hydration_service_" + UUID.randomUUID().toString().replace("-", "")
                + ";MODE=MySQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1";
        var dataSource = new SingleConnectionDataSource(url, "sa", "", true);
        Flyway.configure().dataSource(dataSource).load().migrate();
        jdbc = new JdbcTemplate(dataSource);
        jdbc.update("INSERT INTO users (id,phone,status) VALUES (?,?, 'ACTIVE')", USER_ID, "13000000001");
        jdbc.update("INSERT INTO health_profiles (user_id,current_step,completed) VALUES (?,7,TRUE)", USER_ID);
        when(plans.current(USER_ID)).thenReturn(plan(null, null));
        service = new HydrationService(jdbc, plans, Clock.fixed(NOW, ZoneOffset.UTC));
    }

    @Test
    void resolvesDefaultPlanAndManualTargetPriority() {
        HydrationDtos.SettingsResponse defaults = service.settings(USER_ID);
        assertThat(defaults.defaultCupMl()).isEqualTo(250);
        assertThat(defaults.effectiveTargetMl()).isEqualTo(2000);
        assertThat(defaults.targetSource()).isEqualTo("DEFAULT");
        assertThat(defaults.version()).isZero();

        when(plans.current(USER_ID)).thenReturn(plan(1900, 1));
        HydrationDtos.SettingsResponse planned = service.settings(USER_ID);
        assertThat(planned.effectiveTargetMl()).isEqualTo(1900);
        assertThat(planned.targetSource()).isEqualTo("PLAN");

        when(plans.current(USER_ID)).thenReturn(new PlanDtos.CurrentResponse(
                "NEEDS_RECALCULATION", "plan-1", 1, null, null, null, null, true, plannedTarget(1900)));
        assertThat(service.settings(USER_ID).effectiveTargetMl()).isEqualTo(1900);

        HydrationDtos.SettingsResponse manual = service.updateSettings(USER_ID,
                settingsRequest(2200, 300, 0));
        assertThat(manual.effectiveTargetMl()).isEqualTo(2200);
        assertThat(manual.targetSource()).isEqualTo("USER");
        assertThat(manual.version()).isEqualTo(1);

        when(plans.current(USER_ID)).thenReturn(plan(2000, 2));
        HydrationDtos.SettingsResponse changed = service.settings(USER_ID);
        assertThat(changed.effectiveTargetMl()).isEqualTo(2200);
        assertThat(changed.currentPlanTargetMl()).isEqualTo(2000);
        assertThat(changed.planTargetChanged()).isTrue();

        HydrationDtos.SettingsResponse adopted = service.adoptPlanTarget(USER_ID);
        assertThat(adopted.dailyTargetMl()).isNull();
        assertThat(adopted.effectiveTargetMl()).isEqualTo(2000);
        assertThat(adopted.targetSource()).isEqualTo("PLAN");
        assertThat(adopted.sourcePlanVersion()).isEqualTo(2);
        assertThat(adopted.planTargetChanged()).isFalse();
    }

    @Test
    void validatesSettingsFieldsAndOptimisticVersion() {
        assertField("dailyTargetMl", () -> service.updateSettings(USER_ID, settingsRequest(525, 250, 0)));
        assertField("defaultCupMl", () -> service.updateSettings(USER_ID, settingsRequest(2000, 49, 0)));
        assertField("reminderIntervalMinutes", () -> service.updateSettings(USER_ID,
                new HydrationDtos.SettingsRequest(2000, 250, true, "08:00", "22:00", 10,
                        null, null, 0)));
        assertField("reminderEndTime", () -> service.updateSettings(USER_ID,
                new HydrationDtos.SettingsRequest(2000, 250, true, "08:00", "08:00", 60,
                        null, null, 0)));
        assertField("quietEndTime", () -> service.updateSettings(USER_ID,
                new HydrationDtos.SettingsRequest(2000, 250, true, "08:00", "22:00", 60,
                        "23:00", null, 0)));

        service.updateSettings(USER_ID, settingsRequest(2000, 250, 0));
        assertThatThrownBy(() -> service.updateSettings(USER_ID, settingsRequest(2100, 250, 0)))
                .isInstanceOfSatisfying(ApiException.class, error -> {
                    assertThat(error.code()).isEqualTo("HYDRATION_SETTINGS_VERSION_CONFLICT");
                    assertThat(error.getMessage()).contains("刷新");
                });
    }

    @Test
    void createsIdempotentlyAndReturnsAuthoritativeSummary() {
        var request = entry(250, "2026-09-08T19:30:00+08:00", "Asia/Shanghai", "QUICK");
        HydrationDtos.DayResponse first = service.create(USER_ID, "same-key", request);
        HydrationDtos.DayResponse retried = service.create(USER_ID, "same-key", request);

        assertThat(first.status()).isEqualTo("READY");
        assertThat(first.totalMl()).isEqualTo(250);
        assertThat(first.remainingMl()).isEqualTo(1750);
        assertThat(first.progress()).isEqualByComparingTo("0.1250");
        assertThat(retried.entries()).hasSize(1);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM hydration_entries", Integer.class)).isEqualTo(1);
        assertThat(jdbc.queryForObject("SELECT occurred_at FROM hydration_entries", Timestamp.class).toInstant())
                .isEqualTo(Instant.parse("2026-09-08T11:30:00Z"));
    }

    @Test
    void acceptsAmountBoundsAndRejectsOutOfRangeOrFutureEntries() {
        assertThat(service.create(USER_ID, "one", entry(1, "2026-09-01T08:00:00Z", "Z", "CUSTOM"))
                .totalMl()).isEqualTo(1);
        assertThat(service.create(USER_ID, "max", entry(3000, "2026-09-01T09:00:00Z", "Z", "PRESET"))
                .totalMl()).isEqualTo(3001);
        assertField("amountMl", () -> service.create(USER_ID, "zero",
                entry(0, "2026-09-01T08:00:00Z", "Z", "CUSTOM")));
        assertField("amountMl", () -> service.create(USER_ID, "large",
                entry(3001, "2026-09-01T08:00:00Z", "Z", "CUSTOM")));
        assertField("occurredAt", () -> service.create(USER_ID, "future",
                entry(250, "2026-09-08T12:00:01Z", "Z", "QUICK")));
        assertField("timezone", () -> service.create(USER_ID, "zone",
                entry(250, "2026-09-01T08:00:00Z", "Mars/Base", "QUICK")));
    }

    @Test
    void groupsIanaAndFixedOffsetDatesAcrossMidnight() {
        insert("east", 100, "2026-09-08T16:30:00Z");
        insert("west", 200, "2026-09-08T23:30:00Z");

        assertThat(service.day(USER_ID, LocalDate.of(2026, 9, 9), "Asia/Shanghai").totalMl())
                .isEqualTo(300);
        assertThat(service.day(USER_ID, LocalDate.of(2026, 9, 8), "-04:00").totalMl())
                .isEqualTo(300);
        assertThat(service.day(USER_ID, LocalDate.of(2026, 9, 8), "Asia/Shanghai").totalMl())
                .isZero();
    }

    @Test
    void softDeletesOnlyOwnedActiveEntryAndKeepsCapacitySnapshot() {
        HydrationDtos.DayResponse created = service.create(USER_ID, "delete-key",
                entry(250, "2026-09-01T08:00:00Z", "Z", "QUICK"));
        String id = created.entries().get(0).id();
        service.updateSettings(USER_ID, settingsRequest(2000, 500, 0));

        assertThat(service.day(USER_ID, LocalDate.of(2026, 9, 1), "Z").entries().get(0).amountMl())
                .isEqualTo(250);
        assertThat(service.delete(USER_ID, id, "Z").status()).isEqualTo("EMPTY");
        assertNotFound(() -> service.delete(USER_ID, id, "Z"));
        assertNotFound(() -> service.delete("other-user", id, "Z"));
        assertNotFound(() -> service.delete(USER_ID, "missing", "Z"));
    }

    @Test
    void hidesHistoricalEntriesWhenProfileBecomesIncomplete() {
        insert("historical", 250, "2026-09-01T08:00:00Z");
        jdbc.update("UPDATE health_profiles SET completed=FALSE WHERE user_id=?", USER_ID);

        HydrationDtos.DayResponse day = service.day(USER_ID, LocalDate.of(2026, 9, 1), "UTC");

        assertThat(day.status()).isEqualTo("PROFILE_INCOMPLETE");
        assertThat(day.entries()).isEmpty();
        assertThat(day.totalMl()).isZero();
        assertThatThrownBy(() -> service.delete(USER_ID, "historical", "UTC"))
                .isInstanceOfSatisfying(ApiException.class,
                        error -> assertThat(error.code()).isEqualTo("PROFILE_INCOMPLETE"));
    }

    private HydrationDtos.SettingsRequest settingsRequest(int target, int cup, int version) {
        return new HydrationDtos.SettingsRequest(target, cup, false, "08:00", "22:00", 120,
                null, null, version);
    }

    private HydrationDtos.EntryRequest entry(int amount, String occurredAt, String timezone, String source) {
        return new HydrationDtos.EntryRequest(amount, OffsetDateTime.parse(occurredAt), timezone, source);
    }

    private void insert(String id, int amount, String occurredAt) {
        jdbc.update("INSERT INTO hydration_entries "
                        + "(id,user_id,amount_ml,occurred_at,timezone,source,idempotency_key) VALUES (?,?,?,?,?,?,?)",
                id, USER_ID, amount, Timestamp.from(Instant.parse(occurredAt)), "UTC", "CUSTOM", id);
    }

    private void assertField(String field, org.assertj.core.api.ThrowableAssert.ThrowingCallable call) {
        assertThatThrownBy(call).isInstanceOfSatisfying(ApiException.class,
                error -> assertThat(error.fieldErrors()).extracting("field").contains(field));
    }

    private void assertNotFound(org.assertj.core.api.ThrowableAssert.ThrowingCallable call) {
        assertThatThrownBy(call).isInstanceOfSatisfying(ApiException.class,
                error -> assertThat(error.code()).isEqualTo("HYDRATION_ENTRY_NOT_FOUND"));
    }

    private PlanDtos.CurrentResponse plan(Integer waterMl, Integer version) {
        PlanDtos.PlanResultResponse result = waterMl == null ? null : plannedTarget(waterMl);
        return new PlanDtos.CurrentResponse(waterMl == null ? "EMPTY" : "ACTIVE",
                waterMl == null ? null : "plan-1", version, null, null, null, null, false, result);
    }

    private PlanDtos.PlanResultResponse plannedTarget(int waterMl) {
        return new PlanDtos.PlanResultResponse(
                "FAT_LOSS_V1", true, new BigDecimal("22.0"), 1300, 1800,
                1500, 100, 150, 45, waterMl, 3, 30, new BigDecimal("8.0"),
                new BigDecimal("-0.3"), LocalDate.of(2027, 3, 1), "安全提示");
    }
}
