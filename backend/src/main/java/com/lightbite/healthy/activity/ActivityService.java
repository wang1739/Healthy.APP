package com.lightbite.healthy.activity;

import com.lightbite.healthy.common.api.ApiException;
import com.lightbite.healthy.common.api.ApiFieldError;
import com.lightbite.healthy.plan.PlanDtos;
import com.lightbite.healthy.plan.PlanService;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.DateTimeException;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.TemporalAdjusters;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ActivityService {

    static final String CALCULATION_VERSION = "MET_V1";
    private final JdbcTemplate jdbc;
    private final PlanService plans;
    private final Clock clock;

    @Autowired
    public ActivityService(JdbcTemplate jdbc, PlanService plans) {
        this(jdbc, plans, Clock.systemUTC());
    }

    ActivityService(JdbcTemplate jdbc, PlanService plans, Clock clock) {
        this.jdbc = jdbc;
        this.plans = plans;
        this.clock = clock;
    }

    public List<ActivityDtos.TypeResponse> types(String userId, String query) {
        String normalized = normalize(query == null ? "" : query);
        String pattern = "%" + normalized + "%";
        return jdbc.query("""
                SELECT id,name,category,low_met,medium_met,high_met,type_scope,reference_type_id
                FROM activity_types
                WHERE active=TRUE AND (type_scope='SYSTEM' OR owner_user_id=?)
                  AND normalized_name LIKE ?
                ORDER BY CASE WHEN type_scope='SYSTEM' THEN 0 ELSE 1 END,name
                """, (rs, row) -> type(rs), userId, pattern);
    }

    @Transactional
    public ActivityDtos.TypeResponse createCustomType(
            String userId, ActivityDtos.CustomTypeRequest request
    ) {
        ensureCompleteProfile(userId);
        if (request == null) throw invalid("INVALID_ACTIVITY_TYPE", "name", "请填写自定义运动");
        String name = request.name() == null ? "" : request.name().trim().replaceAll("\\s+", " ");
        String normalized = normalize(name);
        if (normalized.isEmpty() || name.length() > 50) {
            throw invalid("INVALID_ACTIVITY_TYPE_NAME", "name", "运动名称须为 1–50 个字符");
        }
        Map<String, Object> reference;
        try {
            reference = jdbc.queryForMap("""
                    SELECT id,category,low_met,medium_met,high_met
                    FROM activity_types WHERE id=? AND type_scope='SYSTEM' AND active=TRUE
                    """, request.referenceTypeId());
        } catch (EmptyResultDataAccessException exception) {
            throw invalid("INVALID_REFERENCE_ACTIVITY_TYPE", "referenceTypeId", "请选择有效的相似运动");
        }
        String id = UUID.randomUUID().toString();
        try {
            jdbc.update("""
                    INSERT INTO activity_types
                    (id,owner_user_id,uniqueness_scope,name,normalized_name,category,low_met,medium_met,high_met,
                     reference_type_id,type_scope,active,created_at,updated_at)
                    VALUES (?,?,?,?,?,?,?,?,?,?,'USER',TRUE,?,?)
                    """, id, userId, userId, name, normalized, reference.get("category"),
                    reference.get("low_met"), reference.get("medium_met"), reference.get("high_met"),
                    reference.get("id"), now(), now());
        } catch (DataIntegrityViolationException exception) {
            throw invalid("ACTIVITY_TYPE_NAME_EXISTS", "name", "已存在同名自定义运动");
        }
        return ownedType(userId, id);
    }

    public ActivityDtos.DayResponse day(String userId, LocalDate date, String timezone) {
        if (date == null) throw invalid("INVALID_DATE", "date", "请选择日期");
        ZoneId zone = zone(timezone);
        if (!hasCompleteProfile(userId)) {
            return new ActivityDtos.DayResponse(date, "PROFILE_INCOMPLETE", List.of(), 0, 0, 0, "0");
        }
        Instant start = date.atStartOfDay(zone).toInstant();
        Instant end = date.plusDays(1).atStartOfDay(zone).toInstant();
        List<ActivityDtos.RecordResponse> records = records(userId, start, end);
        int minutes = records.stream().mapToInt(ActivityDtos.RecordResponse::durationMinutes).sum();
        int kcal = records.stream().mapToInt(ActivityDtos.RecordResponse::finalKcal).sum();
        String version = records.isEmpty() ? "0" : latestUpdate(userId, start, end).toString();
        return new ActivityDtos.DayResponse(date, records.isEmpty() ? "EMPTY" : "READY", records,
                records.size(), minutes, kcal, version);
    }

    public ActivityDtos.WeekResponse week(String userId, LocalDate date, String timezone) {
        if (date == null) throw invalid("INVALID_DATE", "date", "请选择日期");
        ZoneId zone = zone(timezone);
        LocalDate startDate = date.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
        LocalDate endDate = startDate.plusDays(6);
        if (!hasCompleteProfile(userId)) {
            return new ActivityDtos.WeekResponse(startDate, endDate, "PROFILE_INCOMPLETE", 0, 0, 0,
                    null, null, "PROFILE_INCOMPLETE");
        }
        List<ActivityDtos.RecordResponse> records = records(userId,
                startDate.atStartOfDay(zone).toInstant(), endDate.plusDays(1).atStartOfDay(zone).toInstant());
        int days = (int) records.stream().map(record -> record.occurredAt().atZone(zone).toLocalDate())
                .distinct().count();
        int minutes = records.stream().mapToInt(ActivityDtos.RecordResponse::durationMinutes).sum();
        int kcal = records.stream().mapToInt(ActivityDtos.RecordResponse::finalKcal).sum();
        PlanTarget target = planTarget(userId);
        return new ActivityDtos.WeekResponse(startDate, endDate, target.state(), days, minutes, kcal,
                target.days(), target.minutes(), target.state());
    }

    public ActivityDtos.TodaySummary todaySummary(String userId, LocalDate date, String timezone) {
        return new ActivityDtos.TodaySummary(day(userId, date, timezone), week(userId, date, timezone));
    }

    @Transactional
    public ActivityDtos.MutationResponse create(
            String userId, String idempotencyKey, ActivityDtos.RecordRequest request
    ) {
        ensureCompleteProfile(userId);
        String key = validateKey(idempotencyKey);
        List<String> existing = jdbc.query("SELECT id FROM activity_records WHERE user_id=? AND idempotency_key=?",
                (rs, row) -> rs.getString(1), userId, key);
        if (!existing.isEmpty()) return mutationFor(userId, existing.get(0));
        ValidatedRecord value = validateRecord(userId, request);
        String id = UUID.randomUUID().toString();
        try {
            jdbc.update("""
                    INSERT INTO activity_records
                    (id,user_id,activity_type_id,activity_name_snapshot,intensity,duration_minutes,occurred_at,
                     timezone,weight_kg_snapshot,met_snapshot,calculation_version,estimated_kcal,final_kcal,
                     calorie_source,source,idempotency_key,created_at,updated_at)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,'MANUAL',?,?,?)
                    """, id, userId, value.type().id(), value.type().name(), value.intensity(), value.minutes(),
                    Timestamp.from(value.occurredAt()), value.zone().getId(), value.weight(), value.met(),
                    CALCULATION_VERSION, value.estimatedKcal(), value.finalKcal(), value.calorieSource(), key,
                    now(), now());
        } catch (DataIntegrityViolationException exception) {
            id = jdbc.queryForObject(
                    "SELECT id FROM activity_records WHERE user_id=? AND idempotency_key=?", String.class,
                    userId, key);
        }
        return mutationFor(userId, id);
    }

    @Transactional
    public ActivityDtos.MutationResponse update(
            String userId, String recordId, ActivityDtos.RecordRequest request
    ) {
        requireRecord(userId, recordId);
        ensureCompleteProfile(userId);
        ValidatedRecord value = validateRecord(userId, request);
        int updated = jdbc.update("""
                UPDATE activity_records
                SET activity_type_id=?,activity_name_snapshot=?,intensity=?,duration_minutes=?,occurred_at=?,
                    timezone=?,weight_kg_snapshot=?,met_snapshot=?,calculation_version=?,estimated_kcal=?,
                    final_kcal=?,calorie_source=?,updated_at=?
                WHERE id=? AND user_id=? AND deleted_at IS NULL
                """, value.type().id(), value.type().name(), value.intensity(), value.minutes(),
                Timestamp.from(value.occurredAt()), value.zone().getId(), value.weight(), value.met(),
                CALCULATION_VERSION, value.estimatedKcal(), value.finalKcal(), value.calorieSource(), now(),
                recordId, userId);
        if (updated == 0) throw recordNotFound();
        return mutationFor(userId, recordId);
    }

    @Transactional
    public ActivityDtos.MutationResponse delete(String userId, String recordId, String timezone) {
        ZoneId zone = zone(timezone);
        Map<String, Object> record = requireRecord(userId, recordId);
        ensureCompleteProfile(userId);
        int updated = jdbc.update("""
                UPDATE activity_records SET deleted_at=?,updated_at=?
                WHERE id=? AND user_id=? AND deleted_at IS NULL
                """, now(), now(), recordId, userId);
        if (updated == 0) throw recordNotFound();
        LocalDate date = instant(record.get("occurred_at")).atZone(zone).toLocalDate();
        return new ActivityDtos.MutationResponse(null, day(userId, date, zone.getId()),
                week(userId, date, zone.getId()));
    }

    private ValidatedRecord validateRecord(String userId, ActivityDtos.RecordRequest request) {
        if (request == null) throw invalid("INVALID_ACTIVITY_RECORD", "record", "请填写运动记录");
        ActivityDtos.TypeResponse type = ownedType(userId, request.activityTypeId());
        String intensity = request.intensity() == null ? "" : request.intensity().trim().toUpperCase(Locale.ROOT);
        if (!List.of("LOW", "MEDIUM", "HIGH").contains(intensity)) {
            throw invalid("INVALID_ACTIVITY_INTENSITY", "intensity", "请选择低、中或高强度");
        }
        if (request.durationMinutes() < 1 || request.durationMinutes() > 1440) {
            throw invalid("INVALID_ACTIVITY_DURATION", "durationMinutes", "运动时长须为 1–1440 分钟");
        }
        if (request.occurredAt() == null) {
            throw invalid("INVALID_OCCURRED_AT", "occurredAt", "请选择运动时间");
        }
        Instant occurredAt = request.occurredAt().toInstant();
        if (occurredAt.isAfter(clock.instant())) {
            throw invalid("FUTURE_TIME_NOT_ALLOWED", "occurredAt", "未来时间不能记录运动");
        }
        ZoneId zone = zone(request.timezone());
        BigDecimal weight = latestWeight(userId);
        BigDecimal met = switch (intensity) {
            case "LOW" -> type.lowMet();
            case "MEDIUM" -> type.mediumMet();
            default -> type.highMet();
        };
        int estimate = met.multiply(weight).multiply(BigDecimal.valueOf(request.durationMinutes()))
                .divide(BigDecimal.valueOf(60), 0, RoundingMode.HALF_UP).intValueExact();
        if (estimate > 10000) {
            throw invalid("ACTIVITY_ESTIMATE_TOO_LARGE", "durationMinutes", "预计消耗不能超过 10000 千卡");
        }
        String mode = request.calorieMode() == null ? "" : request.calorieMode().trim().toUpperCase(Locale.ROOT);
        String source;
        int finalKcal;
        if ("ESTIMATED".equals(mode) || "RESTORE_ESTIMATED".equals(mode)) {
            source = "ESTIMATED";
            finalKcal = estimate;
        } else if ("USER_OVERRIDE".equals(mode)) {
            if (request.finalKcal() == null || request.finalKcal() < 0 || request.finalKcal() > 10000) {
                throw invalid("INVALID_FINAL_KCAL", "finalKcal", "运动消耗须为 0–10000 千卡");
            }
            source = "USER_OVERRIDE";
            finalKcal = request.finalKcal();
        } else {
            throw invalid("INVALID_CALORIE_MODE", "calorieMode", "请选择使用估算值、手动修改或恢复估算值");
        }
        return new ValidatedRecord(type, intensity, request.durationMinutes(), occurredAt, zone, weight, met,
                estimate, finalKcal, source);
    }

    private List<ActivityDtos.RecordResponse> records(String userId, Instant start, Instant end) {
        return jdbc.query("""
                SELECT ar.*,at.name type_name,at.category,at.low_met,at.medium_met,at.high_met,
                       at.type_scope,at.reference_type_id
                FROM activity_records ar JOIN activity_types at ON at.id=ar.activity_type_id
                WHERE ar.user_id=? AND ar.occurred_at>=? AND ar.occurred_at<? AND ar.deleted_at IS NULL
                ORDER BY ar.occurred_at DESC,ar.id DESC
                """, (rs, row) -> record(rs), userId, Timestamp.from(start), Timestamp.from(end));
    }

    private ActivityDtos.MutationResponse mutationFor(String userId, String recordId) {
        ActivityDtos.RecordResponse record = record(userId, recordId);
        LocalDate date = record.occurredAt().atZone(zone(record.timezone())).toLocalDate();
        return new ActivityDtos.MutationResponse(record, day(userId, date, record.timezone()),
                week(userId, date, record.timezone()));
    }

    private ActivityDtos.RecordResponse record(String userId, String id) {
        List<ActivityDtos.RecordResponse> rows = jdbc.query("""
                SELECT ar.*,at.name type_name,at.category,at.low_met,at.medium_met,at.high_met,
                       at.type_scope,at.reference_type_id
                FROM activity_records ar JOIN activity_types at ON at.id=ar.activity_type_id
                WHERE ar.id=? AND ar.user_id=? AND ar.deleted_at IS NULL
                """, (rs, row) -> record(rs), id, userId);
        if (rows.isEmpty()) throw recordNotFound();
        return rows.get(0);
    }

    private Map<String, Object> requireRecord(String userId, String id) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT occurred_at FROM activity_records WHERE id=? AND user_id=? AND deleted_at IS NULL",
                id, userId);
        if (rows.isEmpty()) throw recordNotFound();
        return rows.get(0);
    }

    private ActivityDtos.TypeResponse ownedType(String userId, String id) {
        List<ActivityDtos.TypeResponse> rows = jdbc.query("""
                SELECT id,name,category,low_met,medium_met,high_met,type_scope,reference_type_id
                FROM activity_types
                WHERE id=? AND active=TRUE AND (type_scope='SYSTEM' OR owner_user_id=?)
                """, (rs, row) -> type(rs), id, userId);
        if (rows.isEmpty()) throw invalid("INVALID_ACTIVITY_TYPE", "activityTypeId", "请选择有效的运动类型");
        return rows.get(0);
    }

    private PlanTarget planTarget(String userId) {
        PlanDtos.CurrentResponse current = plans.current(userId);
        if (current == null || "EMPTY".equals(current.state())) return new PlanTarget("NO_PLAN", null, null);
        if (!"ACTIVE".equals(current.state()) || current.plan() == null) {
            return new PlanTarget(current.state(), null, null);
        }
        return new PlanTarget("ACTIVE", current.plan().exerciseDays(), current.plan().exerciseMinutes());
    }

    private BigDecimal latestWeight(String userId) {
        List<BigDecimal> values = jdbc.query("""
                SELECT weight_kg FROM body_measurements WHERE user_id=?
                ORDER BY measured_at DESC,id DESC LIMIT 1
                """, (rs, row) -> rs.getBigDecimal(1), userId);
        if (values.isEmpty() || values.get(0) == null || values.get(0).signum() <= 0) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "WEIGHT_REQUIRED", "请先补充有效体重");
        }
        return values.get(0);
    }

    private void ensureCompleteProfile(String userId) {
        if (!hasCompleteProfile(userId)) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "PROFILE_INCOMPLETE", "请先完成健康档案");
        }
    }

    private boolean hasCompleteProfile(String userId) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM health_profiles WHERE user_id=? AND completed=TRUE", Integer.class, userId);
        return count != null && count > 0;
    }

    private String validateKey(String key) {
        if (key == null || key.trim().isEmpty()) {
            throw invalid("IDEMPOTENCY_KEY_REQUIRED", "Idempotency-Key", "新增运动需要 Idempotency-Key");
        }
        if (key.trim().length() > 100) {
            throw invalid("INVALID_IDEMPOTENCY_KEY", "Idempotency-Key", "Idempotency-Key 最多 100 个字符");
        }
        return key.trim();
    }

    private ZoneId zone(String value) {
        if (value == null || value.isBlank()) throw invalid("INVALID_TIMEZONE", "timezone", "请选择时区");
        try {
            return ZoneId.of(value.trim());
        } catch (DateTimeException exception) {
            throw invalid("INVALID_TIMEZONE", "timezone", "时区格式不正确");
        }
    }

    private String normalize(String value) {
        return value == null ? "" : value.trim().replaceAll("\\s+", " ").toLowerCase(Locale.ROOT);
    }

    private Timestamp now() {
        return Timestamp.from(clock.instant());
    }

    private Instant latestUpdate(String userId, Instant start, Instant end) {
        Timestamp value = jdbc.queryForObject("""
                SELECT MAX(updated_at) FROM activity_records
                WHERE user_id=? AND occurred_at>=? AND occurred_at<? AND deleted_at IS NULL
                """, Timestamp.class, userId, Timestamp.from(start), Timestamp.from(end));
        return value == null ? Instant.EPOCH : value.toInstant();
    }

    private Instant instant(Object value) {
        return ((Timestamp) value).toInstant();
    }

    private ActivityDtos.TypeResponse type(ResultSet rs) throws SQLException {
        return new ActivityDtos.TypeResponse(rs.getString("id"), rs.getString("name"), rs.getString("category"),
                rs.getBigDecimal("low_met"), rs.getBigDecimal("medium_met"), rs.getBigDecimal("high_met"),
                rs.getString("type_scope"), rs.getString("reference_type_id"));
    }

    private ActivityDtos.RecordResponse record(ResultSet rs) throws SQLException {
        var type = new ActivityDtos.TypeResponse(rs.getString("activity_type_id"), rs.getString("type_name"),
                rs.getString("category"), rs.getBigDecimal("low_met"), rs.getBigDecimal("medium_met"),
                rs.getBigDecimal("high_met"), rs.getString("type_scope"), rs.getString("reference_type_id"));
        return new ActivityDtos.RecordResponse(rs.getString("id"), type, rs.getString("activity_name_snapshot"),
                rs.getString("intensity"), rs.getInt("duration_minutes"),
                rs.getTimestamp("occurred_at").toInstant(), rs.getString("timezone"),
                rs.getBigDecimal("weight_kg_snapshot"), rs.getBigDecimal("met_snapshot"),
                rs.getString("calculation_version"), rs.getInt("estimated_kcal"), rs.getInt("final_kcal"),
                rs.getString("calorie_source"), rs.getString("source"));
    }

    private ApiException invalid(String code, String field, String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, code, message, List.of(new ApiFieldError(field, message)));
    }

    private ApiException recordNotFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "ACTIVITY_RECORD_NOT_FOUND", "运动记录不存在");
    }

    private record PlanTarget(String state, Integer days, Integer minutes) {
    }

    private record ValidatedRecord(
            ActivityDtos.TypeResponse type, String intensity, int minutes, Instant occurredAt, ZoneId zone,
            BigDecimal weight, BigDecimal met, int estimatedKcal, int finalKcal, String calorieSource
    ) {
    }
}
