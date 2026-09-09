package com.lightbite.healthy.sleep;

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
import java.util.List;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;

class SleepServiceTests {
    private static final String USER = "sleep-user";
    private static final Instant NOW = Instant.parse("2026-09-10T08:00:00Z");
    private final PlanService plans = mock(PlanService.class);
    private JdbcTemplate jdbc;
    private SleepService service;

    @BeforeEach
    void setUp() {
        var dataSource = new SingleConnectionDataSource("jdbc:h2:mem:sleep_service_"
                + UUID.randomUUID().toString().replace("-", "")
                + ";MODE=MySQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1", "sa", "", true);
        Flyway.configure().dataSource(dataSource).load().migrate();
        jdbc = new JdbcTemplate(dataSource);
        profile(USER, "13000000111");
        when(plans.current(USER)).thenReturn(plan("ACTIVE"));
        service = new SleepService(jdbc, plans, Clock.fixed(NOW, ZoneOffset.UTC));
    }

    @Test
    void createsNightAndNapWithServerDurationWakeDateTagsAndIdempotency() {
        var night = service.create(USER, "night-key", request("NIGHT", "2026-09-09T23:30:00+08:00",
                "2026-09-10T07:00:00+08:00", "Asia/Shanghai", 5,
                List.of("STRESS", "NIGHT_AWAKENING"), "  睡得还好  "));
        var retried = service.create(USER, "night-key", request("NAP", "2026-09-01T01:00:00Z",
                "2026-09-01T01:30:00Z", "UTC", null, List.of(), null));
        var nap = service.create(USER, "nap-key", request("NAP", "2026-09-10T12:00:00+08:00",
                "2026-09-10T12:30:00+08:00", "+08:00", null, List.of("CAFFEINE"), null));

        assertThat(night.record().durationMinutes()).isEqualTo(450);
        assertThat(night.record().wakeLocalDate()).isEqualTo(LocalDate.of(2026, 9, 10));
        assertThat(night.record().startedAt()).isEqualTo(Instant.parse("2026-09-09T15:30:00Z"));
        assertThat(night.record().tags()).containsExactly("NIGHT_AWAKENING", "STRESS");
        assertThat(night.record().note()).isEqualTo("睡得还好");
        assertThat(retried.record().id()).isEqualTo(night.record().id());
        assertThat(nap.day().napDurationMinutes()).isEqualTo(30);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM sleep_records", Integer.class)).isEqualTo(2);
    }

    @Test
    void enforcesTypeDurationTimeQualityTagsNotesAndProfile() {
        assertField("duration", () -> create("NIGHT", "2026-09-10T07:31:00Z", "2026-09-10T08:00:00Z"));
        assertField("duration", () -> create("NAP", "2026-09-10T03:00:00Z", "2026-09-10T07:01:00Z"));
        assertField("endedAt", () -> create("NAP", "2026-09-10T07:00:00Z", "2026-09-10T07:00:00Z"));
        assertField("endedAt", () -> create("NAP", "2026-09-10T07:30:00Z", "2026-09-10T08:06:00Z"));
        assertField("recordType", () -> service.create(USER, "bad-type", request("OTHER",
                "2026-09-10T07:00:00Z", "2026-09-10T07:30:00Z", "UTC", null, List.of(), null)));
        assertField("qualityScore", () -> service.create(USER, "bad-quality", request("NAP",
                "2026-09-10T07:00:00Z", "2026-09-10T07:30:00Z", "UTC", 6, List.of(), null)));
        assertField("tags", () -> service.create(USER, "bad-tags", request("NAP",
                "2026-09-10T07:00:00Z", "2026-09-10T07:30:00Z", "UTC", null,
                List.of("STRESS", "STRESS"), null)));
        assertField("tags", () -> service.create(USER, "unknown-tag", request("NAP",
                "2026-09-10T07:00:00Z", "2026-09-10T07:30:00Z", "UTC", null,
                List.of("UNKNOWN"), null)));
        assertField("note", () -> service.create(USER, "bad-note", request("NAP",
                "2026-09-10T07:00:00Z", "2026-09-10T07:30:00Z", "UTC", null, List.of(), "字".repeat(501))));
        assertField("timezone", () -> service.create(USER, "bad-zone", request("NAP",
                "2026-09-10T07:00:00Z", "2026-09-10T07:30:00Z", "Mars/Base", null, List.of(), null)));
        jdbc.update("UPDATE health_profiles SET completed=FALSE WHERE user_id=?", USER);
        assertCode("PROFILE_INCOMPLETE", () -> create("NAP", "2026-09-10T07:00:00Z", "2026-09-10T07:30:00Z"));
    }

    @Test
    void acceptsExactDurationAndClockToleranceBoundaries() {
        assertThat(service.create(USER, "night-min", request("NIGHT", "2026-09-01T00:00:00Z",
                "2026-09-01T00:30:00Z", "UTC", 1, List.of(), "字".repeat(500))).record().durationMinutes())
                .isEqualTo(30);
        assertThat(service.create(USER, "night-max", request("NIGHT", "2026-09-02T00:00:00Z",
                "2026-09-02T16:00:00Z", "UTC", 5, List.of(), null)).record().durationMinutes())
                .isEqualTo(960);
        assertThat(service.create(USER, "nap-min", request("NAP", "2026-09-10T08:00:00Z",
                "2026-09-10T08:05:00Z", "UTC", null, List.of(), null)).record().durationMinutes())
                .isEqualTo(5);
        assertThat(service.create(USER, "nap-max", request("NAP", "2026-09-03T00:00:00Z",
                "2026-09-03T04:00:00Z", "UTC", null, List.of(), null)).record().durationMinutes())
                .isEqualTo(240);
    }

    @Test
    void rejectsOverlapsAndSecondNightButAllowsEditSelfThenSoftDelete() {
        String night = service.create(USER, "first", request("NIGHT", "2026-09-09T22:00:00Z",
                "2026-09-10T06:00:00Z", "UTC", 3, List.of(), null)).record().id();
        assertCode("SLEEP_RECORD_OVERLAP", () -> service.create(USER, "overlap", request("NAP",
                "2026-09-10T05:30:00Z", "2026-09-10T06:30:00Z", "UTC", null, List.of(), null)));
        assertCode("NIGHT_SLEEP_ALREADY_EXISTS", () -> service.create(USER, "second", request("NIGHT",
                "2026-09-09T21:00:00Z", "2026-09-10T05:00:00Z", "UTC", null, List.of(), null)));
        service.create(USER, "nap", request("NAP", "2026-09-10T07:00:00Z",
                "2026-09-10T07:30:00Z", "UTC", null, List.of(), null));
        assertCode("SLEEP_RECORD_OVERLAP", () -> service.create(USER, "nap-overlap", request("NAP",
                "2026-09-10T07:15:00Z", "2026-09-10T07:45:00Z", "UTC", null, List.of(), null)));
        assertCode("SLEEP_RECORD_OVERLAP", () -> service.update(USER, night, request("NAP",
                "2026-09-10T07:10:00Z", "2026-09-10T07:40:00Z", "UTC", null, List.of(), null)));

        var edited = service.update(USER, night, request("NIGHT", "2026-09-09T21:30:00Z",
                "2026-09-10T05:30:00Z", "UTC", 4, List.of("NOISE"), "修改"));
        assertThat(edited.record().durationMinutes()).isEqualTo(480);
        var afterDelete = service.delete(USER, night, "UTC").day();
        assertThat(afterDelete.night()).isNull();
        assertThat(afterDelete.naps()).hasSize(1);
        assertCode("SLEEP_RECORD_NOT_FOUND", () -> service.delete(USER, night, "UTC"));
        assertCode("SLEEP_RECORD_NOT_FOUND", () -> service.update("other", night, request("NIGHT",
                "2026-09-09T21:30:00Z", "2026-09-10T05:30:00Z", "UTC", 4, List.of(), null)));
    }

    @Test
    void calculatesSevenDaySummaryQualityTargetAndPlanStates() {
        service.create(USER, "d1", request("NIGHT", "2026-09-03T22:00:00Z", "2026-09-04T06:00:00Z",
                "UTC", 3, List.of(), null));
        service.create(USER, "d2", request("NIGHT", "2026-09-05T22:00:00Z", "2026-09-06T06:00:00Z",
                "UTC", null, List.of(), null));
        assertThat(service.week(USER, LocalDate.of(2026, 9, 10), "UTC").hasEnoughTrendData()).isFalse();
        service.create(USER, "d3", request("NIGHT", "2026-09-08T21:00:00Z", "2026-09-09T06:00:00Z",
                "UTC", 5, List.of(), null));
        service.create(USER, "nap", request("NAP", "2026-09-09T12:00:00Z", "2026-09-09T12:30:00Z",
                "UTC", 1, List.of(), null));

        var week = service.week(USER, LocalDate.of(2026, 9, 10), "UTC");
        assertThat(week.startDate()).isEqualTo(LocalDate.of(2026, 9, 4));
        assertThat(week.averageNightDurationMinutes()).isEqualTo(500);
        assertThat(week.averageQuality()).isEqualByComparingTo("4.0");
        assertThat(week.napDurationMinutes()).isEqualTo(30);
        assertThat(week.targetMinutes()).isEqualTo(480);
        assertThat(week.targetMetDays()).isEqualTo(3);
        assertThat(week.hasEnoughTrendData()).isTrue();

        when(plans.current(USER)).thenReturn(emptyPlan());
        assertThat(service.week(USER, LocalDate.of(2026, 9, 10), "UTC").planState()).isEqualTo("NO_PLAN");
        assertThat(service.week(USER, LocalDate.of(2026, 9, 10), "UTC").targetMinutes()).isNull();
        for (String state : List.of("PAUSED", "NEEDS_RECALCULATION", "RISK_BLOCKED")) {
            when(plans.current(USER)).thenReturn(plan(state));
            assertThat(service.week(USER, LocalDate.of(2026, 9, 10), "UTC").planState()).isEqualTo(state);
            assertThat(service.week(USER, LocalDate.of(2026, 9, 10), "UTC").targetMinutes()).isNull();
        }
    }

    private void create(String type, String start, String end) {
        service.create(USER, UUID.randomUUID().toString(), request(type, start, end, "UTC", null, List.of(), null));
    }

    private SleepDtos.RecordRequest request(String type, String start, String end, String zone,
                                            Integer quality, List<String> tags, String note) {
        return new SleepDtos.RecordRequest(type, OffsetDateTime.parse(start), OffsetDateTime.parse(end),
                zone, quality, tags, note);
    }

    private void profile(String id, String phone) {
        jdbc.update("INSERT INTO users (id,phone,status) VALUES (?,?,'ACTIVE')", id, phone);
        jdbc.update("INSERT INTO health_profiles (user_id,current_step,completed) VALUES (?,7,TRUE)", id);
    }

    private PlanDtos.CurrentResponse plan(String state) {
        var target = new PlanDtos.PlanResultResponse("FAT_LOSS_V1", true, new BigDecimal("22"), 1300, 1800,
                1500, 100, 150, 45, 2000, 3, 150, new BigDecimal("8"), new BigDecimal("-.3"),
                LocalDate.of(2027, 3, 1), "安全提示");
        return new PlanDtos.CurrentResponse(state, "plan", 1, 1, null, null, null,
                "NEEDS_RECALCULATION".equals(state), "RISK_BLOCKED".equals(state) ? null : target);
    }

    private PlanDtos.CurrentResponse emptyPlan() {
        return new PlanDtos.CurrentResponse("EMPTY", null, null, null, null, null, null, false, null);
    }

    private void assertField(String field, org.assertj.core.api.ThrowableAssert.ThrowingCallable call) {
        assertThatThrownBy(call).isInstanceOfSatisfying(ApiException.class,
                error -> assertThat(error.fieldErrors()).extracting("field").contains(field));
    }

    private void assertCode(String code, org.assertj.core.api.ThrowableAssert.ThrowingCallable call) {
        assertThatThrownBy(call).isInstanceOfSatisfying(ApiException.class,
                error -> assertThat(error.code()).isEqualTo(code));
    }
}
