package com.lightbite.healthy.report;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.Map;
import org.junit.jupiter.api.Test;

class ReportCalculatorTests {
    private final ReportCalculator calculator = new ReportCalculator();

    @Test
    void appliesCeilingHalfCoverageAndFourSufficiencyStates() {
        ReportDtos.Snapshot snapshot = calculator.calculate(facts("WEEKLY", 5, 3, 2, 0, 1, 0), null, "小李");
        assertThat(snapshot.sections()).extracting(ReportDtos.Section::sufficiency)
                .containsExactly("LIMITED", "SUFFICIENT", "LIMITED", "EMPTY", "LIMITED", "NOT_APPLICABLE");
        assertThat(snapshot.completeness()).containsEntry("sufficientSections", 1L);
    }

    @Test
    void dailyOneWeightIsLimitedButOneHealthRecordIsSufficient() {
        ReportDtos.Snapshot snapshot = calculator.calculate(facts("DAILY", 1, 1, 1, 1, 1, 1), null, "小李");
        assertThat(snapshot.sections()).extracting(ReportDtos.Section::sufficiency)
                .containsExactly("LIMITED", "SUFFICIENT", "SUFFICIENT", "SUFFICIENT", "SUFFICIENT", "SUFFICIENT");
    }

    @Test
    void comparisonsRequireBothPeriodsAndAdviceIsStableAndLimitedToThree() {
        ReportDtos.Facts current = facts("WEEKLY", 7, 1, 1, 0, 1, 1);
        ReportDtos.Snapshot snapshot = calculator.calculate(current, facts("WEEKLY", 7, 2, 2, 2, 2, 2), "小李");
        assertThat(snapshot.sections()).allSatisfy(section -> {
            if (!"SUFFICIENT".equals(section.sufficiency())) assertThat(section.previousComparison()).containsEntry("status", "UNAVAILABLE");
        });
        assertThat(snapshot.advice()).hasSize(3);
        assertThat(snapshot.advice()).extracting(ReportDtos.Advice::code).isSorted();
        assertThat(snapshot.rulesVersion()).isEqualTo("REPORT_RULES_V1");
    }

    private ReportDtos.Facts facts(String type, int eligible, int nutritionDays, int hydrationDays,
                                    int activityCount, int sleepDays, int tasks) {
        Instant cutoff = Instant.parse("2026-09-10T04:00:00Z");
        ReportDtos.Period period = new ReportDtos.Period(type, LocalDate.of(2026, 9, 1), LocalDate.of(2026, 9, 7),
                LocalDate.of(2026, 8, 25), LocalDate.of(2026, 8, 31), "Asia/Shanghai", "COMPLETE", eligible,
                cutoff.minusSeconds(604800), cutoff, cutoff, cutoff);
        Map<String, Object> metrics = new LinkedHashMap<>();
        metrics.put("weight", Map.of("count", 1, "latestKg", 60));
        metrics.put("nutrition", Map.of("recordDays", nutritionDays, "averageCalories", 1800));
        metrics.put("hydration", Map.of("recordDays", hydrationDays, "averageDailyMl", 1800));
        metrics.put("activity", Map.of("recordCount", activityCount, "durationMinutes", 60));
        metrics.put("sleep", Map.of("nightDays", sleepDays, "averageNightMinutes", 450));
        metrics.put("tasks", Map.of("totalCount", tasks, "postponedCount", 0, "completionRate", 100));
        return new ReportDtos.Facts(period, "EMPTY", null, Map.of(), metrics, java.util.List.of());
    }
}
