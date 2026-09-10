package com.lightbite.healthy.report;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.lightbite.healthy.common.api.ApiException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import org.junit.jupiter.api.Test;

class ReportPeriodPolicyTests {
    private final Instant now = Instant.parse("2026-09-10T04:00:00Z");
    private final ReportPeriodPolicy policy = new ReportPeriodPolicy(Clock.fixed(now, ZoneOffset.UTC));

    @Test
    void resolvesDailyWeeklyMonthlyAndPreviousPeriods() {
        var daily = policy.resolve("DAILY", LocalDate.of(2026, 9, 10), "Asia/Shanghai", now);
        assertThat(daily.start()).isEqualTo(LocalDate.of(2026, 9, 10));
        assertThat(daily.end()).isEqualTo(LocalDate.of(2026, 9, 10));
        assertThat(daily.previousStart()).isEqualTo(LocalDate.of(2026, 9, 9));
        assertThat(daily.status()).isEqualTo("IN_PROGRESS");
        assertThat(daily.eligibleDays()).isEqualTo(1);

        var weekly = policy.resolve("WEEKLY", LocalDate.of(2026, 9, 13), "Asia/Shanghai", now);
        assertThat(weekly.start()).isEqualTo(LocalDate.of(2026, 9, 7));
        assertThat(weekly.end()).isEqualTo(LocalDate.of(2026, 9, 13));
        assertThat(weekly.previousStart()).isEqualTo(LocalDate.of(2026, 8, 31));
        assertThat(weekly.previousEnd()).isEqualTo(LocalDate.of(2026, 9, 6));
        assertThat(weekly.eligibleDays()).isEqualTo(4);

        var monthly = policy.resolve("MONTHLY", LocalDate.of(2024, 2, 29), "UTC", now);
        assertThat(monthly.start()).isEqualTo(LocalDate.of(2024, 2, 1));
        assertThat(monthly.end()).isEqualTo(LocalDate.of(2024, 2, 29));
        assertThat(monthly.previousStart()).isEqualTo(LocalDate.of(2024, 1, 1));
        assertThat(monthly.status()).isEqualTo("COMPLETE");
    }

    @Test
    void handlesYearBoundaryAndDstUsingLocalMidnights() {
        var year = policy.resolve("WEEKLY", LocalDate.of(2027, 1, 1), "UTC",
                Instant.parse("2027-01-02T00:00:00Z"));
        assertThat(year.start()).isEqualTo(LocalDate.of(2026, 12, 28));
        assertThat(year.end()).isEqualTo(LocalDate.of(2027, 1, 3));

        var dst = policy.resolve("DAILY", LocalDate.of(2026, 3, 8), "America/New_York", now);
        assertThat(dst.endExclusiveInstant().getEpochSecond() - dst.startInstant().getEpochSecond())
                .isEqualTo(23 * 3600L);
    }

    @Test
    void rejectsUnsupportedTypeTimezoneAndFuturePeriodWithChineseFields() {
        assertField("type", () -> policy.resolve("YEARLY", LocalDate.now(), "UTC", now));
        assertField("timezone", () -> policy.resolve("DAILY", LocalDate.now(), "Mars/Base", now));
        assertField("date", () -> policy.resolve("DAILY", LocalDate.of(2026, 9, 11), "Asia/Shanghai", now));
    }

    private void assertField(String field, org.assertj.core.api.ThrowableAssert.ThrowingCallable call) {
        assertThatThrownBy(call).isInstanceOfSatisfying(ApiException.class,
                error -> assertThat(error.fieldErrors()).extracting("field").contains(field));
    }
}
