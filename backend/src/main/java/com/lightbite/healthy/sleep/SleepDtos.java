package com.lightbite.healthy.sleep;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;

public final class SleepDtos {
    private SleepDtos() {
    }

    public record RecordRequest(String recordType, OffsetDateTime startedAt, OffsetDateTime endedAt,
                                String timezone, Integer qualityScore, List<String> tags, String note) {
    }

    public record RecordResponse(String id, String recordType, Instant startedAt, Instant endedAt,
                                 String timezone, LocalDate wakeLocalDate, int durationMinutes,
                                 Integer qualityScore, String qualityLabel, List<String> tags,
                                 String note, String source) {
    }

    public record DayResponse(LocalDate date, String status, RecordResponse night,
                              List<RecordResponse> naps, List<RecordResponse> records,
                              int nightDurationMinutes, int napDurationMinutes,
                              Integer targetMinutes, Integer differenceMinutes, String planState) {
    }

    public record DailyPoint(LocalDate date, Integer nightDurationMinutes, int napDurationMinutes,
                             Integer qualityScore, Boolean targetMet) {
    }

    public record WeekResponse(LocalDate startDate, LocalDate endDate, String status,
                               List<DailyPoint> days, Integer averageNightDurationMinutes,
                               Integer targetMinutes, Integer targetMetDays, BigDecimal averageQuality,
                               int napDurationMinutes, boolean hasEnoughTrendData, String planState) {
    }

    public record MutationResponse(RecordResponse record, DayResponse day, WeekResponse week) {
    }

    public record TodaySummary(DayResponse day, WeekResponse week) {
    }
}
