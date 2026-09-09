package com.lightbite.healthy.activity;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.lightbite.healthy.common.api.ApiException;
import com.lightbite.healthy.plan.PlanDtos;
import com.lightbite.healthy.plan.PlanService;
import java.math.BigDecimal;
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

class ActivityServiceTests {

    private static final String USER = "activity-user";
    private static final Instant NOW = Instant.parse("2026-09-09T12:00:00Z");
    private final PlanService plans = mock(PlanService.class);
    private JdbcTemplate jdbc;
    private ActivityService service;

    @BeforeEach
    void setUp() {
        String url = "jdbc:h2:mem:activity_service_" + UUID.randomUUID().toString().replace("-", "")
                + ";MODE=MySQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1";
        var dataSource = new SingleConnectionDataSource(url, "sa", "", true);
        Flyway.configure().dataSource(dataSource).load().migrate();
        jdbc = new JdbcTemplate(dataSource);
        profile(USER, "13000000001", "60.0");
        when(plans.current(USER)).thenReturn(plan("ACTIVE", 3, 150));
        service = new ActivityService(jdbc, plans, Clock.fixed(NOW, ZoneOffset.UTC));
    }

    @Test
    void listsSearchesAndCreatesUserScopedCustomTypes() {
        assertThat(service.types(USER, null)).hasSize(14);
        assertThat(service.types(USER, "跑")).extracting(ActivityDtos.TypeResponse::name)
                .containsExactly("跑步");

        var custom = service.createCustomType(USER,
                new ActivityDtos.CustomTypeRequest("  室内快走  ", "act-walking"));
        assertThat(custom.name()).isEqualTo("室内快走");
        assertThat(custom.lowMet()).isEqualByComparingTo("2.50");
        assertThat(service.types(USER, "室内")).extracting(ActivityDtos.TypeResponse::id)
                .containsExactly(custom.id());
        assertThat(service.types("someone-else", "室内")).isEmpty();

        assertField("name", () -> service.createCustomType(USER,
                new ActivityDtos.CustomTypeRequest("室内快走", "act-walking")));
        assertField("referenceTypeId", () -> service.createCustomType(USER,
                new ActivityDtos.CustomTypeRequest("无效运动", custom.id())));
    }

    @Test
    void createsIdempotentlyWithMetWeightAndUtcSnapshots() {
        var request = request("act-walking", "MEDIUM", 30,
                "2026-09-08T20:00:00+08:00", "Asia/Shanghai", "ESTIMATED", null);
        var first = service.create(USER, "same-key", request);
        var retried = service.create(USER, "same-key", request);

        assertThat(first.record().estimatedKcal()).isEqualTo(105);
        assertThat(first.record().finalKcal()).isEqualTo(105);
        assertThat(first.record().weightKgSnapshot()).isEqualByComparingTo("60.00");
        assertThat(first.record().metSnapshot()).isEqualByComparingTo("3.50");
        assertThat(first.record().occurredAt()).isEqualTo(Instant.parse("2026-09-08T12:00:00Z"));
        assertThat(first.day().recordCount()).isEqualTo(1);
        assertThat(first.week().exerciseDays()).isEqualTo(1);
        assertThat(first.week().targetExerciseDays()).isEqualTo(3);
        assertThat(first.week().targetDurationMinutes()).isEqualTo(150);
        assertThat(retried.day().records()).hasSize(1);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM activity_records", Integer.class)).isEqualTo(1);
    }

    @Test
    void editsOverridesRestoresAndSoftDeletesOwnedRecord() {
        var created = service.create(USER, "edit-key", request("act-running", "LOW", 30,
                "2026-09-08T10:00:00Z", "UTC", "USER_OVERRIDE", 300));
        String id = created.record().id();
        assertThat(created.record().estimatedKcal()).isEqualTo(180);
        assertThat(created.record().finalKcal()).isEqualTo(300);
        assertThat(created.record().calorieSource()).isEqualTo("USER_OVERRIDE");

        var edited = service.update(USER, id, request("act-running", "MEDIUM", 60,
                "2026-09-08T11:00:00Z", "UTC", "RESTORE_ESTIMATED", null));
        assertThat(edited.record().estimatedKcal()).isEqualTo(498);
        assertThat(edited.record().finalKcal()).isEqualTo(498);
        assertThat(edited.record().calorieSource()).isEqualTo("ESTIMATED");

        assertThat(service.delete(USER, id, "UTC").day().status()).isEqualTo("EMPTY");
        assertNotFound(() -> service.delete(USER, id, "UTC"));
        assertNotFound(() -> service.update("other", id, request("act-running", "LOW", 30,
                "2026-09-08T10:00:00Z", "UTC", "ESTIMATED", null)));
    }

    @Test
    void validatesProfileWeightTimeZoneDurationAndCalories() {
        jdbc.update("UPDATE health_profiles SET completed=FALSE WHERE user_id=?", USER);
        assertThatThrownBy(() -> service.create(USER, "incomplete", request("act-walking", "LOW", 30,
                "2026-09-08T10:00:00Z", "UTC", "ESTIMATED", null)))
                .isInstanceOfSatisfying(ApiException.class,
                        error -> assertThat(error.code()).isEqualTo("PROFILE_INCOMPLETE"));
        jdbc.update("UPDATE health_profiles SET completed=TRUE WHERE user_id=?", USER);
        jdbc.update("DELETE FROM body_measurements WHERE user_id=?", USER);
        assertThatThrownBy(() -> service.create(USER, "no-weight", request("act-walking", "LOW", 30,
                "2026-09-08T10:00:00Z", "UTC", "ESTIMATED", null)))
                .isInstanceOfSatisfying(ApiException.class,
                        error -> assertThat(error.code()).isEqualTo("WEIGHT_REQUIRED"));

        profile("validations", "13000000002", "70");
        when(plans.current("validations")).thenReturn(new PlanDtos.CurrentResponse(
                "EMPTY", null, null, null, null, null, null, false, null));
        assertField("durationMinutes", () -> service.create("validations", "duration",
                request("act-walking", "LOW", 0, "2026-09-08T10:00:00Z", "UTC", "ESTIMATED", null)));
        assertField("occurredAt", () -> service.create("validations", "future",
                request("act-walking", "LOW", 30, "2026-09-09T12:00:01Z", "UTC", "ESTIMATED", null)));
        assertField("timezone", () -> service.create("validations", "zone",
                request("act-walking", "LOW", 30, "2026-09-08T10:00:00Z", "Mars/Base", "ESTIMATED", null)));
        assertField("finalKcal", () -> service.create("validations", "kcal",
                request("act-walking", "LOW", 30, "2026-09-08T10:00:00Z", "UTC", "USER_OVERRIDE", 10001)));
    }

    @Test
    void groupsDatesAndWeeksByRequestedTimezoneAndHidesUnavailablePlanTargets() {
        service.create(USER, "east", request("act-walking", "LOW", 30,
                "2026-09-06T16:30:00Z", "Asia/Shanghai", "ESTIMATED", null));
        service.create(USER, "monday", request("act-walking", "LOW", 40,
                "2026-09-07T16:30:00Z", "Asia/Shanghai", "ESTIMATED", null));
        service.create(USER, "monday-two", request("act-walking", "LOW", 20,
                "2026-09-08T01:00:00+08:00", "Asia/Shanghai", "ESTIMATED", null));

        assertThat(service.day(USER, LocalDate.of(2026, 9, 7), "Asia/Shanghai").recordCount()).isEqualTo(1);
        var week = service.week(USER, LocalDate.of(2026, 9, 8), "Asia/Shanghai");
        assertThat(week.startDate()).isEqualTo(LocalDate.of(2026, 9, 7));
        assertThat(week.endDate()).isEqualTo(LocalDate.of(2026, 9, 13));
        assertThat(week.exerciseDays()).isEqualTo(2);
        assertThat(week.durationMinutes()).isEqualTo(90);

        when(plans.current(USER)).thenReturn(plan("PAUSED", 3, 150));
        assertThat(service.week(USER, LocalDate.of(2026, 9, 8), "UTC").targetExerciseDays()).isNull();
        assertThat(service.week(USER, LocalDate.of(2026, 9, 8), "UTC").planState()).isEqualTo("PAUSED");
    }

    private ActivityDtos.RecordRequest request(String type, String intensity, int minutes, String occurredAt,
                                               String timezone, String calorieMode, Integer finalKcal) {
        return new ActivityDtos.RecordRequest(type, intensity, minutes, OffsetDateTime.parse(occurredAt),
                timezone, calorieMode, finalKcal);
    }

    private void profile(String id, String phone, String weight) {
        jdbc.update("INSERT INTO users (id,phone,status) VALUES (?,?,'ACTIVE')", id, phone);
        jdbc.update("INSERT INTO health_profiles (user_id,current_step,completed) VALUES (?,7,TRUE)", id);
        jdbc.update("INSERT INTO body_measurements (id,user_id,weight_kg,measured_at) VALUES (RANDOM_UUID(),?,?,?)",
                id, new BigDecimal(weight), java.sql.Timestamp.from(Instant.parse("2026-09-01T00:00:00Z")));
    }

    private PlanDtos.CurrentResponse plan(String state, int days, int minutes) {
        var target = new PlanDtos.PlanResultResponse("FAT_LOSS_V1", true, new BigDecimal("22"), 1300, 1800,
                1500, 100, 150, 45, 2000, days, minutes, new BigDecimal("8"), new BigDecimal("-.3"),
                LocalDate.of(2027, 3, 1), "安全提示");
        return new PlanDtos.CurrentResponse(state, "plan", 1, 1, null, null, null,
                "NEEDS_RECALCULATION".equals(state), "RISK_BLOCKED".equals(state) ? null : target);
    }

    private void assertField(String field, org.assertj.core.api.ThrowableAssert.ThrowingCallable call) {
        assertThatThrownBy(call).isInstanceOfSatisfying(ApiException.class,
                error -> assertThat(error.fieldErrors()).extracting("field").contains(field));
    }

    private void assertNotFound(org.assertj.core.api.ThrowableAssert.ThrowingCallable call) {
        assertThatThrownBy(call).isInstanceOfSatisfying(ApiException.class,
                error -> assertThat(error.code()).isEqualTo("ACTIVITY_RECORD_NOT_FOUND"));
    }
}
