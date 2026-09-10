package com.lightbite.healthy.report;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.lightbite.healthy.common.api.ApiException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.ObjectMapper;

@SpringBootTest
@ActiveProfiles("test")
class ReportServiceTests {
    private static final String USER_A = "report-service-a";
    private static final String USER_B = "report-service-b";
    private static final LocalDate DATE = LocalDate.of(2026, 9, 10);
    private static final ReportDtos.GenerateRequest REQUEST =
            new ReportDtos.GenerateRequest("DAILY", DATE, "Asia/Shanghai");

    @Autowired JdbcTemplate jdbc;
    @Autowired ObjectMapper json;
    @Autowired ReportPeriodPolicy periods;
    @Autowired ReportDataCollector collector;
    @Autowired ReportCalculator calculator;
    @Autowired PlatformTransactionManager transactionManager;
    @Autowired ReportService reports;

    @BeforeEach
    void setUp() {
        jdbc.update("DELETE FROM health_report_sources");
        jdbc.update("DELETE FROM health_reports");
        jdbc.update("DELETE FROM meal_entries WHERE user_id IN (?,?)", USER_A, USER_B);
        for (String id : List.of(USER_A, USER_B)) {
            jdbc.update("MERGE INTO users (id,phone,display_name,status) KEY(id) VALUES (?,?,?,'ACTIVE')", id,
                    USER_A.equals(id) ? "13000000981" : "13000000982", USER_A.equals(id) ? "甲用户" : "乙用户");
            jdbc.update("MERGE INTO health_profiles (user_id,current_step,completed) KEY(user_id) VALUES (?,7,TRUE)", id);
        }
    }

    @Test
    void validatesKeyBoundaryAndConflictingReuse() {
        String key100 = "k".repeat(100);
        var first = reports.generate(USER_A, key100, REQUEST);
        assertThat(reports.generate(USER_A, key100, REQUEST).id()).isEqualTo(first.id());
        assertThatThrownBy(() -> reports.generate(USER_A, key100,
                new ReportDtos.GenerateRequest("MONTHLY", DATE, "Asia/Shanghai")))
                .isInstanceOfSatisfying(ApiException.class, error -> {
                    assertThat(error.code()).isEqualTo("IDEMPOTENCY_KEY_CONFLICT");
                    assertThat(error.getMessage()).isEqualTo("Idempotency-Key 已用于其他报告请求");
                });
        assertThatThrownBy(() -> reports.generate(USER_A, "k".repeat(101), REQUEST))
                .isInstanceOfSatisfying(ApiException.class,
                        error -> assertThat(error.getMessage()).isEqualTo("Idempotency-Key 最多 100 个字符"));
    }

    @Test
    void reusesStableInputDetectsSourceChangeAndKeepsCreatedSemantic() {
        var first = reports.generate(USER_A, "stable-1", REQUEST);
        jdbc.update("UPDATE users SET display_name='昵称变化' WHERE id=?", USER_A);
        var unchanged = reports.generate(USER_A, "stable-2", REQUEST);
        assertThat(unchanged.id()).isEqualTo(first.id());
        assertThat(unchanged.version()).isEqualTo(1);
        assertThat(unchanged.created()).isFalse();
        assertThat(reports.detail(USER_A, first.id()).created()).isFalse();

        meal("service-meal-1", 1800);
        assertThat(reports.detail(USER_A, first.id()).sourceDataChanged()).isTrue();
        var second = reports.generate(USER_A, "changed-1", REQUEST);
        assertThat(second.version()).isEqualTo(2);
        assertThat(second.id()).isNotEqualTo(first.id());
        assertThat(reports.detail(USER_A, first.id()).snapshot().toString()).isEqualTo(first.snapshot().toString());
    }

    @Test
    void repeatedDeleteIsStableSourcesArePrivateAndRegenerationNeverReusesVersion() {
        meal("service-meal-2", 1600);
        var first = reports.generate(USER_A, "delete-1", REQUEST);
        assertThat(reports.sources(USER_A, first.id(), null, null)).isNotEmpty();
        assertThatThrownBy(() -> reports.sources(USER_B, first.id(), null, null))
                .isInstanceOfSatisfying(ApiException.class, error -> assertThat(error.code()).isEqualTo("REPORT_NOT_FOUND"));
        assertThat(reports.delete(USER_A, first.id()).deleted()).isTrue();
        assertThat(reports.delete(USER_A, first.id()).deleted()).isTrue();
        assertThatThrownBy(() -> reports.delete(USER_B, first.id()))
                .isInstanceOfSatisfying(ApiException.class, error -> assertThat(error.code()).isEqualTo("REPORT_NOT_FOUND"));

        var regenerated = reports.generate(USER_A, "delete-2", REQUEST);
        assertThat(regenerated.version()).isEqualTo(2);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM meal_entries WHERE user_id=?", Integer.class, USER_A)).isEqualTo(1);
    }

    @Test
    void duplicateSourceFailureRollsBackReportAndAllSources() {
        var period = periods.resolve("DAILY", DATE, "Asia/Shanghai", Instant.parse("2026-09-10T06:00:00Z"));
        var duplicate = new ReportDtos.Source("NUTRITION", "intake", "MEAL_ENTRY", "same-source", DATE,
                "饮食记录", Instant.parse("2026-09-10T05:00:00Z"));
        ReportDataCollector brokenCollector = mock(ReportDataCollector.class);
        when(brokenCollector.collect(any(), any())).thenReturn(facts(period, List.of(duplicate, duplicate)));
        ReportService service = service(brokenCollector, calculator, Clock.fixed(period.dataCutoffAt(), ZoneOffset.UTC));

        assertThatThrownBy(() -> service.generate(USER_A, "rollback-1", REQUEST)).isInstanceOf(RuntimeException.class);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM health_reports WHERE user_id=?", Integer.class, USER_A)).isZero();
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM health_report_sources", Integer.class)).isZero();
    }

    @Test
    void independentServiceInstancesUseUniqueConstraintAndRetryConcurrentWinner() throws Exception {
        Instant cutoff = Instant.parse("2026-09-10T06:00:00Z");
        var period = periods.resolve("DAILY", DATE, "Asia/Shanghai", cutoff);
        ReportDataCollector stableCollector = mock(ReportDataCollector.class);
        when(stableCollector.collect(any(), any())).thenAnswer(call -> facts(call.getArgument(1), List.of()));
        ReportCalculator synchronizedCalculator = mock(ReportCalculator.class);
        CountDownLatch bothCalculated = new CountDownLatch(2);
        when(synchronizedCalculator.calculate(any(), any(), any())).thenAnswer(call -> {
            bothCalculated.countDown();
            assertThat(bothCalculated.await(5, TimeUnit.SECONDS)).isTrue();
            return snapshot(call.getArgument(0));
        });
        ReportService first = service(stableCollector, synchronizedCalculator, Clock.fixed(cutoff, ZoneOffset.UTC));
        ReportService second = service(stableCollector, synchronizedCalculator, Clock.fixed(cutoff, ZoneOffset.UTC));

        var executor = Executors.newFixedThreadPool(2);
        try {
            CountDownLatch start = new CountDownLatch(1);
            Future<ReportDtos.ReportResponse> a = executor.submit(() -> { start.await(); return first.generate(USER_A, "race-a", REQUEST); });
            Future<ReportDtos.ReportResponse> b = executor.submit(() -> { start.await(); return second.generate(USER_A, "race-b", REQUEST); });
            start.countDown();
            assertThat(a.get().id()).isEqualTo(b.get().id());
            assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM health_reports WHERE user_id=?", Integer.class, USER_A)).isEqualTo(1);
        } finally {
            executor.shutdownNow();
        }
    }

    private ReportService service(ReportDataCollector dataCollector, ReportCalculator reportCalculator, Clock clock) {
        return new ReportService(jdbc, json, periods, dataCollector, reportCalculator, clock,
                new TransactionTemplate(transactionManager));
    }

    private ReportDtos.Facts facts(ReportDtos.Period period, List<ReportDtos.Source> sources) {
        Map<String, Object> metrics = new LinkedHashMap<>();
        for (String key : List.of("weight", "nutrition", "hydration", "activity", "sleep", "tasks"))
            metrics.put(key, Map.of());
        return new ReportDtos.Facts(period, "EMPTY", null, Map.of(), metrics, sources);
    }

    private ReportDtos.Snapshot snapshot(ReportDtos.Facts facts) {
        return new ReportDtos.Snapshot(Map.of("type", facts.period().type()), "甲用户", "测试结论", List.of(), List.of(),
                Map.of(), List.of(), ReportCalculator.RULES_VERSION, facts.period().dataCutoffAt(),
                "本报告仅用于健康记录回顾，不构成医疗诊断或治疗建议。");
    }

    private void meal(String id, int calories) {
        jdbc.update("""
                INSERT INTO meal_entries(id,user_id,entry_date,meal_type,food_name_snapshot,grams,calories_snapshot,
                  protein_snapshot,carbs_snapshot,fat_snapshot,idempotency_key,updated_at)
                VALUES(?, ?, ?, 'DINNER', '测试餐', 100, ?, 20, 30, 10, ?, '2026-09-10 05:00:00')
                """, id, USER_A, DATE, calories, id);
    }
}
