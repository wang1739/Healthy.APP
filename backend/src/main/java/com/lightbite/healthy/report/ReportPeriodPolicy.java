package com.lightbite.healthy.report;

import com.lightbite.healthy.common.api.ApiException;
import com.lightbite.healthy.common.api.ApiFieldError;
import java.time.Clock;
import java.time.DateTimeException;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.TemporalAdjusters;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

@Component
public class ReportPeriodPolicy {
    private static final Set<String> TYPES = Set.of("DAILY", "WEEKLY", "MONTHLY");
    private final Clock clock;

    public ReportPeriodPolicy() {
        this(Clock.systemUTC());
    }

    ReportPeriodPolicy(Clock clock) {
        this.clock = clock;
    }

    public ReportDtos.Period resolve(String type, LocalDate date, String timezone) {
        return resolve(type, date, timezone, clock.instant());
    }

    ReportDtos.Period resolve(String type, LocalDate date, String timezone, Instant cutoff) {
        String normalized = type == null ? "" : type.trim().toUpperCase(Locale.ROOT);
        if (!TYPES.contains(normalized)) throw invalid("type", "报告类型不正确");
        if (date == null) throw invalid("date", "请选择报告日期");
        if (cutoff == null) throw invalid("date", "报告截止时间不正确");
        ZoneId zone;
        try {
            zone = ZoneId.of(timezone == null ? "" : timezone.trim());
        } catch (DateTimeException exception) {
            throw invalid("timezone", "时区不正确");
        }
        LocalDate start = switch (normalized) {
            case "WEEKLY" -> date.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
            case "MONTHLY" -> date.withDayOfMonth(1);
            default -> date;
        };
        LocalDate end = switch (normalized) {
            case "WEEKLY" -> start.plusDays(6);
            case "MONTHLY" -> start.plusMonths(1).minusDays(1);
            default -> start;
        };
        LocalDate today = cutoff.atZone(zone).toLocalDate();
        if (start.isAfter(today)) throw invalid("date", "不能生成未来周期的报告");
        LocalDate previousStart = switch (normalized) {
            case "WEEKLY" -> start.minusWeeks(1);
            case "MONTHLY" -> start.minusMonths(1);
            default -> start.minusDays(1);
        };
        LocalDate previousEnd = start.minusDays(1);
        Instant startInstant = start.atStartOfDay(zone).toInstant();
        Instant endExclusive = end.plusDays(1).atStartOfDay(zone).toInstant();
        Instant queryCutoff = cutoff;
        int eligibleDays = (int) (java.time.temporal.ChronoUnit.DAYS.between(
                start, end.isBefore(today) ? end : today) + 1);
        return new ReportDtos.Period(normalized, start, end, previousStart, previousEnd, zone.getId(),
                end.isBefore(today) ? "COMPLETE" : "IN_PROGRESS", eligibleDays,
                startInstant, endExclusive, queryCutoff, cutoff);
    }

    private ApiException invalid(String field, String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, "INVALID_REPORT_PERIOD", message,
                List.of(new ApiFieldError(field, message)));
    }
}
