package com.lightbite.healthy.sleep;

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
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class SleepService {
    private static final Set<String> TAGS = Set.of(
            "STRESS", "CAFFEINE", "ALCOHOL", "SCREEN_TIME", "NIGHT_AWAKENING", "NOISE", "DISCOMFORT");
    private final JdbcTemplate jdbc;
    private final PlanService plans;
    private final Clock clock;

    @Autowired
    public SleepService(JdbcTemplate jdbc, PlanService plans) {
        this(jdbc, plans, Clock.systemUTC());
    }

    SleepService(JdbcTemplate jdbc, PlanService plans, Clock clock) {
        this.jdbc = jdbc;
        this.plans = plans;
        this.clock = clock;
    }

    public SleepDtos.DayResponse day(String userId, LocalDate date, String timezone) {
        if (date == null) throw invalid("INVALID_DATE", "date", "请选择日期");
        zone(timezone);
        if (!hasCompleteProfile(userId)) return new SleepDtos.DayResponse(date, "PROFILE_INCOMPLETE",
                null, List.of(), List.of(), 0, 0, null, null, "PROFILE_INCOMPLETE");
        List<SleepDtos.RecordResponse> records = records(userId, date, date);
        SleepDtos.RecordResponse night = records.stream().filter(r -> "NIGHT".equals(r.recordType())).findFirst().orElse(null);
        List<SleepDtos.RecordResponse> naps = records.stream().filter(r -> "NAP".equals(r.recordType())).toList();
        int nightMinutes = night == null ? 0 : night.durationMinutes();
        int napMinutes = naps.stream().mapToInt(SleepDtos.RecordResponse::durationMinutes).sum();
        PlanTarget target = planTarget(userId);
        Integer difference = target.minutes() == null || night == null ? null : nightMinutes - target.minutes();
        return new SleepDtos.DayResponse(date, records.isEmpty() ? "EMPTY" : "READY", night, naps, records,
                nightMinutes, napMinutes, target.minutes(), difference, target.state());
    }

    public SleepDtos.WeekResponse week(String userId, LocalDate date, String timezone) {
        if (date == null) throw invalid("INVALID_DATE", "date", "请选择日期");
        zone(timezone);
        LocalDate start = date.minusDays(6);
        if (!hasCompleteProfile(userId)) return new SleepDtos.WeekResponse(start, date, "PROFILE_INCOMPLETE",
                List.of(), null, null, null, null, 0, false, "PROFILE_INCOMPLETE");
        List<SleepDtos.RecordResponse> records = records(userId, start, date);
        PlanTarget target = planTarget(userId);
        List<SleepDtos.DailyPoint> points = new ArrayList<>();
        int nightCount = 0;
        int nightMinutes = 0;
        int qualityCount = 0;
        int qualityTotal = 0;
        int napMinutes = 0;
        int metDays = 0;
        for (LocalDate current = start; !current.isAfter(date); current = current.plusDays(1)) {
            LocalDate pointDate = current;
            List<SleepDtos.RecordResponse> dayRecords = records.stream()
                    .filter(record -> record.wakeLocalDate().equals(pointDate)).toList();
            SleepDtos.RecordResponse night = dayRecords.stream()
                    .filter(record -> "NIGHT".equals(record.recordType())).findFirst().orElse(null);
            int naps = dayRecords.stream().filter(record -> "NAP".equals(record.recordType()))
                    .mapToInt(SleepDtos.RecordResponse::durationMinutes).sum();
            napMinutes += naps;
            Integer duration = night == null ? null : night.durationMinutes();
            Integer quality = night == null ? null : night.qualityScore();
            Boolean met = target.minutes() == null || night == null ? null : duration >= target.minutes();
            if (night != null) {
                nightCount++;
                nightMinutes += duration;
                if (Boolean.TRUE.equals(met)) metDays++;
                if (quality != null) { qualityCount++; qualityTotal += quality; }
            }
            points.add(new SleepDtos.DailyPoint(current, duration, naps, quality, met));
        }
        Integer average = nightCount == 0 ? null : BigDecimal.valueOf(nightMinutes)
                .divide(BigDecimal.valueOf(nightCount), 0, RoundingMode.HALF_UP).intValue();
        BigDecimal averageQuality = qualityCount == 0 ? null : BigDecimal.valueOf(qualityTotal)
                .divide(BigDecimal.valueOf(qualityCount), 1, RoundingMode.HALF_UP);
        return new SleepDtos.WeekResponse(start, date, target.state(), points, average, target.minutes(),
                target.minutes() == null ? null : metDays, averageQuality, napMinutes, nightCount >= 3, target.state());
    }

    public SleepDtos.TodaySummary todaySummary(String userId, LocalDate date, String timezone) {
        return new SleepDtos.TodaySummary(day(userId, date, timezone), week(userId, date, timezone));
    }

    @Transactional
    public SleepDtos.MutationResponse create(String userId, String idempotencyKey, SleepDtos.RecordRequest request) {
        ensureCompleteProfile(userId);
        String key = validateKey(idempotencyKey);
        List<String> existing = jdbc.query("SELECT id FROM sleep_records WHERE user_id=? AND idempotency_key=?",
                (rs, row) -> rs.getString(1), userId, key);
        if (!existing.isEmpty()) return mutationFor(userId, existing.get(0));
        Validated value = validate(userId, request, null, key);
        String id = UUID.randomUUID().toString();
        try {
            jdbc.update("""
                    INSERT INTO sleep_records
                    (id,user_id,record_type,started_at,ended_at,timezone,wake_local_date,active_night_wake_date,duration_minutes,
                     quality_score,note,source,idempotency_key,created_at,updated_at)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,'MANUAL',?,?,?)
                    """, id, userId, value.type(), Timestamp.from(value.start()), Timestamp.from(value.end()),
                    value.zone().getId(), value.wakeDate(), "NIGHT".equals(value.type()) ? value.wakeDate() : null,
                    value.minutes(), value.quality(), value.note(), key,
                    now(), now());
            insertTags(id, value.tags());
        } catch (DataIntegrityViolationException exception) {
            List<String> raced = jdbc.query("SELECT id FROM sleep_records WHERE user_id=? AND idempotency_key=?",
                    (rs, row) -> rs.getString(1), userId, key);
            if (raced.isEmpty()) throw conflict("NIGHT_SLEEP_ALREADY_EXISTS", "当天已有夜间睡眠，请编辑原记录");
            id = raced.get(0);
        }
        return mutationFor(userId, id);
    }

    @Transactional
    public SleepDtos.MutationResponse update(String userId, String recordId, SleepDtos.RecordRequest request) {
        requireRecord(userId, recordId);
        ensureCompleteProfile(userId);
        Validated value = validate(userId, request, recordId, null);
        jdbc.update("""
                UPDATE sleep_records SET record_type=?,started_at=?,ended_at=?,timezone=?,wake_local_date=?,
                active_night_wake_date=?,duration_minutes=?,quality_score=?,note=?,updated_at=?
                WHERE id=? AND user_id=? AND deleted_at IS NULL
                """, value.type(), Timestamp.from(value.start()), Timestamp.from(value.end()), value.zone().getId(),
                value.wakeDate(), "NIGHT".equals(value.type()) ? value.wakeDate() : null,
                value.minutes(), value.quality(), value.note(), now(), recordId, userId);
        jdbc.update("DELETE FROM sleep_record_tags WHERE sleep_record_id=?", recordId);
        insertTags(recordId, value.tags());
        return mutationFor(userId, recordId);
    }

    @Transactional
    public SleepDtos.MutationResponse delete(String userId, String recordId, String timezone) {
        zone(timezone);
        Map<String, Object> record = requireRecord(userId, recordId);
        ensureCompleteProfile(userId);
        jdbc.update("UPDATE sleep_records SET deleted_at=?,active_night_wake_date=NULL,updated_at=? "
                        + "WHERE id=? AND user_id=? AND deleted_at IS NULL",
                now(), now(), recordId, userId);
        LocalDate date = localDate(record.get("wake_local_date"));
        return new SleepDtos.MutationResponse(null, day(userId, date, timezone), week(userId, date, timezone));
    }

    private Validated validate(String userId, SleepDtos.RecordRequest request, String excludedId, String idempotencyKey) {
        if (request == null) throw invalid("INVALID_SLEEP_RECORD", "record", "请填写睡眠记录");
        String type = request.recordType() == null ? "" : request.recordType().trim().toUpperCase(Locale.ROOT);
        if (!Set.of("NIGHT", "NAP").contains(type))
            throw invalid("INVALID_SLEEP_TYPE", "recordType", "请选择夜间睡眠或午睡");
        if (request.startedAt() == null) throw invalid("INVALID_STARTED_AT", "startedAt", "请选择入睡时间");
        if (request.endedAt() == null) throw invalid("INVALID_ENDED_AT", "endedAt", "请选择醒来时间");
        Instant start = request.startedAt().toInstant();
        Instant end = request.endedAt().toInstant();
        if (!end.isAfter(start)) throw invalid("INVALID_SLEEP_INTERVAL", "endedAt", "醒来时间必须晚于入睡时间");
        if (end.isAfter(clock.instant().plus(Duration.ofMinutes(5))))
            throw invalid("FUTURE_TIME_NOT_ALLOWED", "endedAt", "未来时间不能记录睡眠");
        long minutes = Duration.between(start, end).toMinutes();
        int minimum = "NIGHT".equals(type) ? 30 : 5;
        int maximum = "NIGHT".equals(type) ? 960 : 240;
        if (minutes < minimum || minutes > maximum)
            throw invalid("INVALID_SLEEP_DURATION", "duration", "睡眠时长不符合所选类型范围");
        ZoneId zone = zone(request.timezone());
        LocalDate wakeDate = end.atZone(zone).toLocalDate();
        if (request.qualityScore() != null && (request.qualityScore() < 1 || request.qualityScore() > 5))
            throw invalid("INVALID_SLEEP_QUALITY", "qualityScore", "睡眠质量须为 1–5");
        List<String> tags = request.tags() == null ? List.of() : request.tags().stream()
                .map(tag -> tag == null ? "" : tag.trim().toUpperCase(Locale.ROOT)).sorted().toList();
        if (new HashSet<>(tags).size() != tags.size() || !TAGS.containsAll(tags))
            throw invalid("INVALID_SLEEP_TAGS", "tags", "睡眠影响标签不正确或重复");
        String note = request.note() == null ? null : request.note().trim();
        if (note != null && note.isEmpty()) note = null;
        if (note != null && note.length() > 500)
            throw invalid("INVALID_SLEEP_NOTE", "note", "备注最多 500 个字符");
        if ("NIGHT".equals(type) && count("""
                SELECT COUNT(*) FROM sleep_records WHERE user_id=? AND wake_local_date=? AND record_type='NIGHT'
                AND deleted_at IS NULL AND (? IS NULL OR id<>?) AND (? IS NULL OR idempotency_key<>?)
                """, userId, wakeDate, excludedId, excludedId, idempotencyKey, idempotencyKey) > 0)
            throw conflict("NIGHT_SLEEP_ALREADY_EXISTS", "当天已有夜间睡眠，请编辑原记录");
        if (count("""
                SELECT COUNT(*) FROM sleep_records WHERE user_id=? AND deleted_at IS NULL
                AND started_at<? AND ended_at>? AND (? IS NULL OR id<>?) AND (? IS NULL OR idempotency_key<>?)
                """, userId, Timestamp.from(end), Timestamp.from(start), excludedId, excludedId,
                idempotencyKey, idempotencyKey) > 0)
            throw conflict("SLEEP_RECORD_OVERLAP", "睡眠时间与已有记录重叠");
        return new Validated(type, start, end, zone, wakeDate, (int) minutes,
                request.qualityScore(), tags, note);
    }

    private List<SleepDtos.RecordResponse> records(String userId, LocalDate start, LocalDate end) {
        return jdbc.query("""
                SELECT * FROM sleep_records WHERE user_id=? AND wake_local_date BETWEEN ? AND ?
                AND deleted_at IS NULL ORDER BY ended_at DESC,id DESC
                """, (rs, row) -> record(rs), userId, start, end);
    }

    private SleepDtos.RecordResponse record(String userId, String id) {
        List<SleepDtos.RecordResponse> values = jdbc.query(
                "SELECT * FROM sleep_records WHERE id=? AND user_id=? AND deleted_at IS NULL",
                (rs, row) -> record(rs), id, userId);
        if (values.isEmpty()) throw notFound();
        return values.get(0);
    }

    private SleepDtos.RecordResponse record(ResultSet rs) throws SQLException {
        String id = rs.getString("id");
        Integer quality = (Integer) rs.getObject("quality_score");
        List<String> tags = jdbc.query("SELECT tag_code FROM sleep_record_tags WHERE sleep_record_id=? ORDER BY tag_code",
                (tagRs, row) -> tagRs.getString(1), id);
        return new SleepDtos.RecordResponse(id, rs.getString("record_type"),
                rs.getTimestamp("started_at").toInstant(), rs.getTimestamp("ended_at").toInstant(),
                rs.getString("timezone"), rs.getObject("wake_local_date", LocalDate.class),
                rs.getInt("duration_minutes"), quality, qualityLabel(quality), tags,
                rs.getString("note"), rs.getString("source"));
    }

    private SleepDtos.MutationResponse mutationFor(String userId, String id) {
        SleepDtos.RecordResponse record = record(userId, id);
        return new SleepDtos.MutationResponse(record, day(userId, record.wakeLocalDate(), record.timezone()),
                week(userId, record.wakeLocalDate(), record.timezone()));
    }

    private void insertTags(String id, List<String> tags) {
        for (String tag : tags) jdbc.update("INSERT INTO sleep_record_tags VALUES (?,?)", id, tag);
    }

    private Map<String, Object> requireRecord(String userId, String id) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT wake_local_date FROM sleep_records WHERE id=? AND user_id=? AND deleted_at IS NULL", id, userId);
        if (rows.isEmpty()) throw notFound();
        return rows.get(0);
    }

    private PlanTarget planTarget(String userId) {
        PlanDtos.CurrentResponse current = plans.current(userId);
        if (current == null || "EMPTY".equals(current.state())) return new PlanTarget("NO_PLAN", null);
        if (!"ACTIVE".equals(current.state()) || current.plan() == null) return new PlanTarget(current.state(), null);
        int minutes = current.plan().sleepHours().multiply(BigDecimal.valueOf(60))
                .setScale(0, RoundingMode.HALF_UP).intValue();
        return new PlanTarget("ACTIVE", minutes);
    }

    private boolean hasCompleteProfile(String userId) {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM health_profiles WHERE user_id=? AND completed=TRUE",
                Integer.class, userId);
        return count != null && count > 0;
    }

    private void ensureCompleteProfile(String userId) {
        if (!hasCompleteProfile(userId))
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "PROFILE_INCOMPLETE", "请先完成健康档案");
    }

    private String validateKey(String key) {
        if (key == null || key.isBlank())
            throw invalid("IDEMPOTENCY_KEY_REQUIRED", "Idempotency-Key", "新增睡眠需要 Idempotency-Key");
        if (key.trim().length() > 100)
            throw invalid("INVALID_IDEMPOTENCY_KEY", "Idempotency-Key", "Idempotency-Key 最多 100 个字符");
        return key.trim();
    }

    private ZoneId zone(String value) {
        if (value == null || value.isBlank()) throw invalid("INVALID_TIMEZONE", "timezone", "请选择时区");
        try { return ZoneId.of(value.trim()); }
        catch (DateTimeException exception) { throw invalid("INVALID_TIMEZONE", "timezone", "时区格式不正确"); }
    }

    private int count(String sql, Object... args) {
        Integer count = jdbc.queryForObject(sql, Integer.class, args);
        return count == null ? 0 : count;
    }

    private Timestamp now() { return Timestamp.from(clock.instant()); }

    private LocalDate localDate(Object value) {
        return value instanceof LocalDate date ? date : ((java.sql.Date) value).toLocalDate();
    }

    private String qualityLabel(Integer score) {
        if (score == null) return "未评价";
        return List.of("", "很差", "较差", "一般", "良好", "很好").get(score);
    }

    private ApiException invalid(String code, String field, String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, code, message, List.of(new ApiFieldError(field, message)));
    }

    private ApiException conflict(String code, String message) {
        return new ApiException(HttpStatus.CONFLICT, code, message);
    }

    private ApiException notFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "SLEEP_RECORD_NOT_FOUND", "睡眠记录不存在");
    }

    private record PlanTarget(String state, Integer minutes) { }
    private record Validated(String type, Instant start, Instant end, ZoneId zone, LocalDate wakeDate,
                             int minutes, Integer quality, List<String> tags, String note) { }
}
