package com.lightbite.healthy.hydration;

import com.lightbite.healthy.common.api.ApiException;
import com.lightbite.healthy.common.api.ApiFieldError;
import com.lightbite.healthy.plan.PlanDtos;
import com.lightbite.healthy.plan.PlanService;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Time;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.DateTimeException;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class HydrationService {

    private static final int DEFAULT_TARGET_ML = 2000;
    private static final int DEFAULT_CUP_ML = 250;
    private final JdbcTemplate jdbc;
    private final PlanService plans;
    private final Clock clock;

    @Autowired
    public HydrationService(JdbcTemplate jdbc, PlanService plans) {
        this(jdbc, plans, Clock.systemUTC());
    }

    HydrationService(JdbcTemplate jdbc, PlanService plans, Clock clock) {
        this.jdbc = jdbc;
        this.plans = plans;
        this.clock = clock;
    }

    public HydrationDtos.SettingsResponse settings(String userId) {
        PlanTarget plan = planTarget(userId);
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT * FROM hydration_settings WHERE user_id=?", userId);
        return rows.isEmpty() ? defaultSettings(plan) : settingsResponse(rows.get(0), plan);
    }

    @Transactional
    public HydrationDtos.SettingsResponse updateSettings(
            String userId, HydrationDtos.SettingsRequest request
    ) {
        ensureCompleteProfile(userId);
        if (request == null) throw invalid("INVALID_HYDRATION_SETTINGS", "settings", "请填写饮水设置");
        PlanTarget plan = planTarget(userId);
        List<Map<String, Object>> existingRows = jdbc.queryForList(
                "SELECT daily_target_ml,version FROM hydration_settings WHERE user_id=?", userId);
        Integer existingVersion = existingRows.isEmpty() ? null : number(existingRows.get(0), "version");
        Integer existingTarget = existingRows.isEmpty()
                ? null : nullableInt(existingRows.get(0).get("daily_target_ml"));
        Integer target = request.dailyTargetMl() == null ? existingTarget : request.dailyTargetMl();
        ValidatedSettings value = validateSettings(request, target);
        String targetSource = target != null ? "USER" : plan.amountMl() != null ? "PLAN" : "DEFAULT";
        int expected = request.version() == null ? -1 : request.version();
        if (existingVersion == null) {
            if (expected != 0) throw versionConflict();
            try {
                jdbc.update("""
                        INSERT INTO hydration_settings
                        (user_id,daily_target_ml,default_cup_ml,reminder_enabled,reminder_start_time,
                         reminder_end_time,reminder_interval_minutes,quiet_start_time,quiet_end_time,
                         target_source,source_plan_version,version,updated_at)
                        VALUES (?,?,?,?,?,?,?,?,?,?,?,1,?)
                        """, userId, value.dailyTargetMl(), value.defaultCupMl(), value.reminderEnabled(),
                        Time.valueOf(value.reminderStart()), Time.valueOf(value.reminderEnd()),
                        value.reminderIntervalMinutes(), sqlTime(value.quietStart()), sqlTime(value.quietEnd()),
                        targetSource, plan.version(), Timestamp.from(clock.instant()));
            } catch (DataIntegrityViolationException exception) {
                throw versionConflict();
            }
        } else {
            if (expected != existingVersion) throw versionConflict();
            int updated = jdbc.update("""
                    UPDATE hydration_settings
                    SET daily_target_ml=?,default_cup_ml=?,reminder_enabled=?,reminder_start_time=?,
                        reminder_end_time=?,reminder_interval_minutes=?,quiet_start_time=?,quiet_end_time=?,
                        target_source=?,source_plan_version=?,version=version+1,updated_at=?
                    WHERE user_id=? AND version=?
                    """, value.dailyTargetMl(), value.defaultCupMl(), value.reminderEnabled(),
                    Time.valueOf(value.reminderStart()), Time.valueOf(value.reminderEnd()),
                    value.reminderIntervalMinutes(), sqlTime(value.quietStart()), sqlTime(value.quietEnd()),
                    targetSource, plan.version(), Timestamp.from(clock.instant()), userId, expected);
            if (updated == 0) throw versionConflict();
        }
        return settings(userId);
    }

    @Transactional
    public HydrationDtos.SettingsResponse adoptPlanTarget(String userId) {
        ensureCompleteProfile(userId);
        PlanTarget plan = planTarget(userId);
        if (plan.amountMl() == null) {
            throw invalid("PLAN_TARGET_UNAVAILABLE", "dailyTargetMl", "当前没有可采用的计划饮水目标");
        }
        int updated = jdbc.update("""
                UPDATE hydration_settings
                SET daily_target_ml=NULL,target_source='PLAN',source_plan_version=?,version=version+1,updated_at=?
                WHERE user_id=?
                """, plan.version(), Timestamp.from(clock.instant()), userId);
        if (updated == 0) {
            jdbc.update("""
                    INSERT INTO hydration_settings
                    (user_id,daily_target_ml,target_source,source_plan_version,version,updated_at)
                    VALUES (?,NULL,'PLAN',?,1,?)
                    """, userId, plan.version(), Timestamp.from(clock.instant()));
        }
        return settings(userId);
    }

    public HydrationDtos.DayResponse day(String userId, LocalDate date, String timezone) {
        if (date == null) throw invalid("INVALID_DATE", "date", "请选择日期");
        ZoneId zone = zone(timezone);
        if (!hasCompleteProfile(userId)) {
            HydrationDtos.SettingsResponse settings = settings(userId);
            return new HydrationDtos.DayResponse(date, "PROFILE_INCOMPLETE", List.of(), 0,
                    settings.effectiveTargetMl(), settings.effectiveTargetMl(), BigDecimal.ZERO.setScale(4),
                    settings.targetSource(), settings);
        }
        Instant start = date.atStartOfDay(zone).toInstant();
        Instant end = date.plusDays(1).atStartOfDay(zone).toInstant();
        List<HydrationDtos.EntryResponse> entries = jdbc.query("""
                SELECT id,amount_ml,occurred_at,timezone,source FROM hydration_entries
                WHERE user_id=? AND occurred_at>=? AND occurred_at<? AND deleted_at IS NULL
                ORDER BY occurred_at DESC,id DESC
                """, (rs, rowNum) -> entry(rs), userId, Timestamp.from(start), Timestamp.from(end));
        int total = entries.stream().mapToInt(HydrationDtos.EntryResponse::amountMl).sum();
        HydrationDtos.SettingsResponse settings = settings(userId);
        int target = settings.effectiveTargetMl();
        BigDecimal progress = BigDecimal.valueOf(total).divide(BigDecimal.valueOf(target), 4, RoundingMode.HALF_UP);
        return new HydrationDtos.DayResponse(date, entries.isEmpty() ? "EMPTY" : "READY", entries,
                total, target, Math.max(0, target - total), progress, settings.targetSource(), settings);
    }

    @Transactional
    public HydrationDtos.DayResponse create(
            String userId, String idempotencyKey, HydrationDtos.EntryRequest request
    ) {
        ensureCompleteProfile(userId);
        String key = validateKey(idempotencyKey);
        List<Map<String, Object>> existing = jdbc.queryForList(
                "SELECT occurred_at,timezone FROM hydration_entries WHERE user_id=? AND idempotency_key=?",
                userId, key);
        if (!existing.isEmpty()) {
            Instant occurredAt = instant(existing.get(0).get("occurred_at"));
            ZoneId originalZone = zone(existing.get(0).get("timezone").toString());
            return day(userId, occurredAt.atZone(originalZone).toLocalDate(), originalZone.getId());
        }
        ValidatedEntry value = validateEntry(request);
        try {
            jdbc.update("""
                    INSERT INTO hydration_entries
                    (id,user_id,amount_ml,occurred_at,timezone,source,idempotency_key,created_at,updated_at)
                    VALUES (?,?,?,?,?,?,?,?,?)
                    """, UUID.randomUUID().toString(), userId, value.amountMl(), Timestamp.from(value.occurredAt()),
                    value.zone().getId(), value.source(), key, Timestamp.from(clock.instant()),
                    Timestamp.from(clock.instant()));
        } catch (DataIntegrityViolationException exception) {
            Map<String, Object> row = jdbc.queryForMap(
                    "SELECT occurred_at,timezone FROM hydration_entries WHERE user_id=? AND idempotency_key=?",
                    userId, key);
            Instant occurredAt = instant(row.get("occurred_at"));
            ZoneId originalZone = zone(row.get("timezone").toString());
            return day(userId, occurredAt.atZone(originalZone).toLocalDate(), originalZone.getId());
        }
        LocalDate date = value.occurredAt().atZone(value.zone()).toLocalDate();
        return day(userId, date, value.zone().getId());
    }

    @Transactional
    public HydrationDtos.DayResponse delete(String userId, String entryId, String timezone) {
        ZoneId zone = zone(timezone);
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT occurred_at FROM hydration_entries WHERE id=? AND user_id=? AND deleted_at IS NULL",
                entryId, userId);
        if (rows.isEmpty()) throw entryNotFound();
        ensureCompleteProfile(userId);
        Instant occurredAt = instant(rows.get(0).get("occurred_at"));
        int updated = jdbc.update("""
                UPDATE hydration_entries SET deleted_at=?,updated_at=?
                WHERE id=? AND user_id=? AND deleted_at IS NULL
                """, Timestamp.from(clock.instant()), Timestamp.from(clock.instant()), entryId, userId);
        if (updated == 0) throw entryNotFound();
        return day(userId, occurredAt.atZone(zone).toLocalDate(), zone.getId());
    }

    private HydrationDtos.SettingsResponse defaultSettings(PlanTarget plan) {
        int target = plan.amountMl() == null ? DEFAULT_TARGET_ML : plan.amountMl();
        String source = plan.amountMl() == null ? "DEFAULT" : "PLAN";
        return new HydrationDtos.SettingsResponse(null, target, DEFAULT_CUP_ML, false,
                "08:00", "22:00", 120, null, null, source, plan.amountMl(), null, false, 0);
    }

    private HydrationDtos.SettingsResponse settingsResponse(Map<String, Object> row, PlanTarget plan) {
        Integer manual = nullableInt(row.get("daily_target_ml"));
        String source = manual != null ? "USER" : plan.amountMl() != null ? "PLAN" : "DEFAULT";
        int effective = manual != null ? manual : plan.amountMl() != null ? plan.amountMl() : DEFAULT_TARGET_ML;
        Integer sourceVersion = nullableInt(row.get("source_plan_version"));
        boolean changed = manual != null && plan.version() != null && !plan.version().equals(sourceVersion);
        return new HydrationDtos.SettingsResponse(manual, effective, number(row, "default_cup_ml"),
                bool(row, "reminder_enabled"), time(row.get("reminder_start_time")),
                time(row.get("reminder_end_time")), number(row, "reminder_interval_minutes"),
                time(row.get("quiet_start_time")), time(row.get("quiet_end_time")), source,
                plan.amountMl(), sourceVersion, changed, number(row, "version"));
    }

    private ValidatedSettings validateSettings(HydrationDtos.SettingsRequest request, Integer target) {
        if (target != null && (target < 500 || target > 6000 || target % 50 != 0)) {
            throw invalid("INVALID_DAILY_TARGET", "dailyTargetMl", "每日目标须为 500–6000 ml 且按 50 ml 调整");
        }
        Integer cup = request.defaultCupMl();
        if (cup == null || cup < 50 || cup > 2000) {
            throw invalid("INVALID_DEFAULT_CUP", "defaultCupMl", "默认杯量须为 50–2000 ml");
        }
        Integer interval = request.reminderIntervalMinutes();
        if (interval == null || interval < 15 || interval > 720) {
            throw invalid("INVALID_REMINDER_INTERVAL", "reminderIntervalMinutes", "提醒间隔须为 15–720 分钟");
        }
        if (request.reminderEnabled() == null) {
            throw invalid("INVALID_REMINDER_ENABLED", "reminderEnabled", "请选择是否开启提醒");
        }
        LocalTime start = parseTime(request.reminderStartTime(), "reminderStartTime", "请输入提醒开始时间");
        LocalTime end = parseTime(request.reminderEndTime(), "reminderEndTime", "请输入提醒结束时间");
        if (start.equals(end)) {
            throw invalid("INVALID_REMINDER_RANGE", "reminderEndTime", "提醒开始和结束时间不能相同");
        }
        if ((request.quietStartTime() == null) != (request.quietEndTime() == null)) {
            throw invalid("INVALID_QUIET_RANGE", "quietEndTime", "勿扰开始和结束时间须同时填写");
        }
        LocalTime quietStart = request.quietStartTime() == null ? null
                : parseTime(request.quietStartTime(), "quietStartTime", "请输入勿扰开始时间");
        LocalTime quietEnd = request.quietEndTime() == null ? null
                : parseTime(request.quietEndTime(), "quietEndTime", "请输入勿扰结束时间");
        if (quietStart != null && quietStart.equals(quietEnd)) {
            throw invalid("INVALID_QUIET_RANGE", "quietEndTime", "勿扰开始和结束时间不能相同");
        }
        return new ValidatedSettings(target, cup, Boolean.TRUE.equals(request.reminderEnabled()),
                start, end, interval, quietStart, quietEnd);
    }

    private ValidatedEntry validateEntry(HydrationDtos.EntryRequest request) {
        if (request == null) throw invalid("INVALID_HYDRATION_ENTRY", "entry", "请填写饮水记录");
        if (request.amountMl() < 1 || request.amountMl() > 3000) {
            throw invalid("INVALID_HYDRATION_AMOUNT", "amountMl", "单次饮水量须为 1–3000 ml");
        }
        if (request.occurredAt() == null) {
            throw invalid("INVALID_OCCURRED_AT", "occurredAt", "请选择饮水时间");
        }
        Instant occurredAt = request.occurredAt().toInstant();
        if (occurredAt.isAfter(clock.instant())) {
            throw invalid("FUTURE_TIME_NOT_ALLOWED", "occurredAt", "未来时间不能记录饮水");
        }
        ZoneId zone = zone(request.timezone());
        String source = request.source() == null ? "" : request.source().trim().toUpperCase();
        if (!List.of("QUICK", "PRESET", "CUSTOM").contains(source)) {
            throw invalid("INVALID_HYDRATION_SOURCE", "source", "饮水记录来源不受支持");
        }
        return new ValidatedEntry(request.amountMl(), occurredAt, zone, source);
    }

    private PlanTarget planTarget(String userId) {
        PlanDtos.CurrentResponse current = plans.current(userId);
        if (current == null || "PAUSED".equals(current.state()) || current.plan() == null) {
            return new PlanTarget(null, null);
        }
        return new PlanTarget(current.plan().waterMl(), current.currentVersion());
    }

    private void ensureCompleteProfile(String userId) {
        if (!hasCompleteProfile(userId)) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "PROFILE_INCOMPLETE", "请先完成健康档案");
        }
    }

    private boolean hasCompleteProfile(String userId) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM health_profiles WHERE user_id=? AND completed=TRUE",
                Integer.class, userId);
        return count != null && count > 0;
    }

    private String validateKey(String key) {
        if (key == null || key.trim().isEmpty()) {
            throw invalid("IDEMPOTENCY_KEY_REQUIRED", "Idempotency-Key", "新增饮水需要 Idempotency-Key");
        }
        if (key.trim().length() > 100) {
            throw invalid("INVALID_IDEMPOTENCY_KEY", "Idempotency-Key", "Idempotency-Key 最多 100 个字符");
        }
        return key.trim();
    }

    private ZoneId zone(String value) {
        if (value == null || value.isBlank()) {
            throw invalid("INVALID_TIMEZONE", "timezone", "请选择时区");
        }
        try {
            return ZoneId.of(value.trim());
        } catch (DateTimeException exception) {
            throw invalid("INVALID_TIMEZONE", "timezone", "时区格式不正确");
        }
    }

    private LocalTime parseTime(String value, String field, String message) {
        try {
            return LocalTime.parse(value);
        } catch (RuntimeException exception) {
            throw invalid("INVALID_TIME", field, message);
        }
    }

    private HydrationDtos.EntryResponse entry(ResultSet rs) throws SQLException {
        return new HydrationDtos.EntryResponse(rs.getString("id"), rs.getInt("amount_ml"),
                rs.getTimestamp("occurred_at").toInstant(), rs.getString("timezone"), rs.getString("source"));
    }

    private ApiException invalid(String code, String field, String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, code, message, List.of(new ApiFieldError(field, message)));
    }

    private ApiException versionConflict() {
        return new ApiException(HttpStatus.CONFLICT, "HYDRATION_SETTINGS_VERSION_CONFLICT",
                "饮水设置已更新，请刷新后重试");
    }

    private ApiException entryNotFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "HYDRATION_ENTRY_NOT_FOUND", "饮水记录不存在");
    }

    private Time sqlTime(LocalTime value) {
        return value == null ? null : Time.valueOf(value);
    }

    private String time(Object value) {
        if (value == null) return null;
        LocalTime time = value instanceof LocalTime local ? local : ((Time) value).toLocalTime();
        return time.withSecond(0).withNano(0).toString();
    }

    private int number(Map<String, Object> row, String key) {
        return ((Number) row.get(key)).intValue();
    }

    private Integer nullableInt(Object value) {
        return value == null ? null : ((Number) value).intValue();
    }

    private boolean bool(Map<String, Object> row, String key) {
        return Boolean.TRUE.equals(row.get(key));
    }

    private Instant instant(Object value) {
        return ((Timestamp) value).toInstant();
    }

    private record PlanTarget(Integer amountMl, Integer version) {
    }

    private record ValidatedSettings(
            Integer dailyTargetMl, int defaultCupMl, boolean reminderEnabled,
            LocalTime reminderStart, LocalTime reminderEnd, int reminderIntervalMinutes,
            LocalTime quietStart, LocalTime quietEnd
    ) {
    }

    private record ValidatedEntry(int amountMl, Instant occurredAt, ZoneId zone, String source) {
    }
}
