package com.lightbite.healthy.tasks;

import com.lightbite.healthy.common.api.ApiException;
import com.lightbite.healthy.common.api.ApiFieldError;
import java.time.DateTimeException;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Set;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

@Component
public class TaskSchedulePolicy {
    private static final Set<String> TYPES = Set.of("NONE", "DAILY", "WEEKDAYS", "WEEKENDS", "WEEKLY_DAYS");

    public void validateRule(String type, Integer weekdaysMask, LocalDate effectiveDate) {
        if (effectiveDate == null) throw invalid("date", "请选择任务日期");
        if (type == null || !TYPES.contains(type)) throw invalid("recurrenceType", "重复规则不正确");
        if ("WEEKLY_DAYS".equals(type)) {
            if (weekdaysMask == null || weekdaysMask < 1 || weekdaysMask > 127)
                throw invalid("weekdaysMask", "请至少选择一个有效星期");
        } else if (weekdaysMask != null) {
            throw invalid("weekdaysMask", "当前重复规则不能设置星期");
        }
    }

    public boolean matches(String type, Integer weekdaysMask, LocalDate date, LocalDate effectiveDate) {
        validateRule(type, weekdaysMask, effectiveDate);
        if (date == null || date.isBefore(effectiveDate)) return false;
        int weekday = date.getDayOfWeek().getValue() - 1;
        return switch (type) {
            case "NONE" -> date.equals(effectiveDate);
            case "DAILY" -> true;
            case "WEEKDAYS" -> weekday < 5;
            case "WEEKENDS" -> weekday >= 5;
            case "WEEKLY_DAYS" -> (weekdaysMask & (1 << weekday)) != 0;
            default -> false;
        };
    }

    public boolean shouldEnsure(LocalDate requested, LocalDate today) {
        if (requested == null || today == null) throw invalid("date", "请选择日期");
        if (requested.isAfter(today.plusDays(7))) throw invalid("date", "最多只能查看未来 7 天");
        return !requested.isBefore(today);
    }

    public ZoneId zone(String timezone) {
        if (timezone == null || timezone.isBlank()) throw invalid("timezone", "请选择时区");
        try {
            return ZoneId.of(timezone.trim());
        } catch (DateTimeException exception) {
            throw invalid("timezone", "时区格式不正确");
        }
    }

    public Instant toInstant(LocalDate date, LocalTime time, String timezone) {
        if (date == null) throw invalid("date", "请选择日期");
        if (time == null) throw invalid("localTime", "请选择任务时间");
        ZoneId zone = zone(timezone);
        LocalDateTime local = LocalDateTime.of(date, time);
        List<ZoneOffset> offsets = zone.getRules().getValidOffsets(local);
        if (offsets.size() != 1) throw invalid("localTime", offsets.isEmpty()
                ? "该本地时间因夏令时不存在，请重新选择" : "该本地时间因夏令时重复，请重新选择");
        return local.toInstant(offsets.get(0));
    }

    private ApiException invalid(String field, String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, "INVALID_TASK_SCHEDULE", message,
                List.of(new ApiFieldError(field, message)));
    }
}
