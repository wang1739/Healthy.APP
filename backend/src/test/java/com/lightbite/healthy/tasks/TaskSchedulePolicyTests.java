package com.lightbite.healthy.tasks;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.lightbite.healthy.common.api.ApiException;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import org.junit.jupiter.api.Test;

class TaskSchedulePolicyTests {

    private final TaskSchedulePolicy policy = new TaskSchedulePolicy();

    @Test
    void matchesAllSupportedRecurrenceRules() {
        LocalDate monday = LocalDate.of(2026, 9, 7);
        assertThat(policy.matches("NONE", null, monday, monday)).isTrue();
        assertThat(policy.matches("NONE", null, monday.plusDays(1), monday)).isFalse();
        assertThat(policy.matches("DAILY", null, monday.plusDays(6), monday)).isTrue();
        assertThat(policy.matches("WEEKDAYS", null, monday, monday)).isTrue();
        assertThat(policy.matches("WEEKDAYS", null, monday.plusDays(5), monday)).isFalse();
        assertThat(policy.matches("WEEKENDS", null, monday.plusDays(5), monday)).isTrue();
        assertThat(policy.matches("WEEKLY_DAYS", (1 << 0) | (1 << 4), monday, monday)).isTrue();
        assertThat(policy.matches("WEEKLY_DAYS", (1 << 0) | (1 << 4), monday.plusDays(1), monday)).isFalse();
    }

    @Test
    void rejectsInvalidRulesAndMasksWithChineseFieldErrors() {
        assertField("recurrenceType", () -> policy.validateRule("MONTHLY", null, LocalDate.now()));
        assertField("weekdaysMask", () -> policy.validateRule("WEEKLY_DAYS", 0, LocalDate.now()));
        assertField("weekdaysMask", () -> policy.validateRule("WEEKLY_DAYS", 128, LocalDate.now()));
        assertField("date", () -> policy.validateRule("NONE", null, null));
    }

    @Test
    void convertsShanghaiAndFixedOffsetButRejectsDstGapAndOverlap() {
        assertThat(policy.toInstant(LocalDate.of(2026, 9, 10), LocalTime.of(8, 0), "Asia/Shanghai"))
                .isEqualTo(Instant.parse("2026-09-10T00:00:00Z"));
        assertThat(policy.toInstant(LocalDate.of(2026, 9, 10), LocalTime.of(8, 0), "+08:00"))
                .isEqualTo(Instant.parse("2026-09-10T00:00:00Z"));
        assertField("localTime", () -> policy.toInstant(LocalDate.of(2026, 3, 8),
                LocalTime.of(2, 30), "America/New_York"));
        assertField("localTime", () -> policy.toInstant(LocalDate.of(2026, 11, 1),
                LocalTime.of(1, 30), "America/New_York"));
        assertField("timezone", () -> policy.toInstant(LocalDate.now(), LocalTime.NOON, "Mars/Base"));
    }

    @Test
    void validatesGenerationWindowWithoutBackfillingHistory() {
        LocalDate today = LocalDate.of(2026, 9, 10);
        assertThat(policy.shouldEnsure(today, today)).isTrue();
        assertThat(policy.shouldEnsure(today.plusDays(7), today)).isTrue();
        assertThat(policy.shouldEnsure(today.minusDays(1), today)).isFalse();
        assertField("date", () -> policy.shouldEnsure(today.plusDays(8), today));
    }

    private void assertField(String field, org.assertj.core.api.ThrowableAssert.ThrowingCallable call) {
        assertThatThrownBy(call).isInstanceOfSatisfying(ApiException.class,
                error -> assertThat(error.fieldErrors()).extracting("field").contains(field));
    }
}
