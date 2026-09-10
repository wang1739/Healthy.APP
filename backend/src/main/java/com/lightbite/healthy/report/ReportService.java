package com.lightbite.healthy.report;

import com.lightbite.healthy.common.api.ApiException;
import com.lightbite.healthy.common.api.ApiFieldError;
import java.security.MessageDigest;
import java.sql.Date;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

@Service
public class ReportService {
    private final JdbcTemplate jdbc;
    private final ObjectMapper json;
    private final ReportPeriodPolicy periods;
    private final ReportDataCollector collector;
    private final ReportCalculator calculator;
    private final Clock clock;
    private final TransactionTemplate transactions;

    @Autowired
    public ReportService(JdbcTemplate jdbc, ObjectMapper json, ReportPeriodPolicy periods,
                         ReportDataCollector collector, ReportCalculator calculator,
                         PlatformTransactionManager transactionManager) {
        this(jdbc, json, periods, collector, calculator, Clock.systemUTC(), new TransactionTemplate(transactionManager));
    }

    ReportService(JdbcTemplate jdbc, ObjectMapper json, ReportPeriodPolicy periods,
                  ReportDataCollector collector, ReportCalculator calculator, Clock clock,
                  TransactionTemplate transactions) {
        this.jdbc = jdbc; this.json = json; this.periods = periods; this.collector = collector;
        this.calculator = calculator; this.clock = clock; this.transactions = transactions;
    }

    public synchronized ReportDtos.ReportResponse generate(String userId, String key, ReportDtos.GenerateRequest request) {
        validateKey(key);
        if (request == null) throw invalid("request", "请提交报告周期");
        Instant cutoff = clock.instant();
        ReportDtos.Period period = periods.resolve(request.type(), request.date(), request.timezone(), cutoff);
        List<Row> sameKey = rows("WHERE user_id=? AND idempotency_key=?", userId, key.trim());
        if (!sameKey.isEmpty()) {
            Row row = sameKey.get(0);
            if (!row.type.equals(period.type()) || !row.start.equals(period.start()) || !row.timezone.equals(period.timezone()))
                throw new ApiException(HttpStatus.CONFLICT, "IDEMPOTENCY_KEY_CONFLICT", "Idempotency-Key 已用于其他报告请求");
            return response(row, false, false);
        }
        ensureUser(userId);
        ensureProfile(userId);
        ReportDtos.Facts facts = collector.collect(userId, period);
        String hash = hash(facts);
        List<Row> latest = rows("WHERE user_id=? AND report_type=? AND period_start=? AND deleted_at IS NULL ORDER BY version DESC LIMIT 1",
                userId, period.type(), Date.valueOf(period.start()));
        if (!latest.isEmpty() && latest.get(0).inputHash.equals(hash)) return response(latest.get(0), false, false);

        ReportDtos.Period previousPeriod = periods.resolve(period.type(), period.previousStart(), period.timezone(), cutoff);
        ReportDtos.Facts previous = collector.collect(userId, previousPeriod);
        String displayName = jdbc.queryForObject("SELECT display_name FROM users WHERE id=?", String.class, userId);
        ReportDtos.Snapshot snapshot = calculator.calculate(facts, previous, displayName);
        int version = latest.isEmpty() ? 1 : latest.get(0).version + 1;
        String id = UUID.randomUUID().toString();
        Instant createdAt = clock.instant();
        transactions.executeWithoutResult(ignored -> {
            jdbc.update("""
                    INSERT INTO health_reports(id,user_id,report_type,period_start,period_end,timezone,period_status,version,
                      rules_version,data_cutoff_at,input_hash,snapshot_json,idempotency_key,created_at)
                    VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                    """, id, userId, period.type(), Date.valueOf(period.start()), Date.valueOf(period.end()), period.timezone(),
                    period.status(), version, ReportCalculator.RULES_VERSION, Timestamp.from(period.dataCutoffAt()), hash,
                    json.writeValueAsString(snapshot), key.trim(), Timestamp.from(createdAt));
            for (ReportDtos.Source source : facts.sources()) jdbc.update("""
                    INSERT INTO health_report_sources(report_id,section_code,metric_code,source_type,source_id,source_local_date,location_label)
                    VALUES(?,?,?,?,?,?,?)
                    """, id, source.section(), source.metric(), source.sourceType(), source.sourceId(),
                    source.localDate() == null ? null : Date.valueOf(source.localDate()), source.locationLabel());
        });
        Row row = new Row(id, userId, period.type(), period.start(), period.end(), period.timezone(), period.status(), version,
                period.dataCutoffAt(), hash, json.valueToTree(snapshot), key.trim(), null, createdAt);
        return response(row, true, false);
    }

    public List<ReportDtos.ReportSummary> list(String userId, String type, LocalDate date, String timezone) {
        String where = "WHERE user_id=? AND deleted_at IS NULL";
        java.util.ArrayList<Object> args = new java.util.ArrayList<>(); args.add(userId);
        if (type != null && !type.isBlank()) {
            ReportDtos.Period p = date == null
                    ? periods.resolve(type, clock.instant().atZone(java.time.ZoneOffset.UTC).toLocalDate(), "UTC")
                    : periods.resolve(type, date, timezone);
            where += " AND report_type=?"; args.add(p.type());
            if (date != null) { where += " AND period_start=?"; args.add(Date.valueOf(p.start())); }
        } else if (date != null) throw invalid("type", "按日期查询时请选择报告类型");
        List<Row> rows = rows(where + " ORDER BY created_at DESC, version DESC", args.toArray());
        Map<String, Integer> max = new LinkedHashMap<>();
        rows.forEach(r -> max.merge(r.type + r.start, r.version, Math::max));
        return rows.stream().map(r -> new ReportDtos.ReportSummary(r.id, r.type, r.start, r.end, r.timezone, r.status,
                r.version, r.version == max.get(r.type + r.start), changed(userId, r), r.createdAt,
                r.snapshot.path("conclusion").asText(""))).toList();
    }

    public ReportDtos.ReportResponse detail(String userId, String id) {
        Row row = owned(userId, id); return response(row, isLatest(row), changed(userId, row));
    }

    public List<ReportDtos.SourceResponse> sources(String userId, String id, String section, String metric) {
        owned(userId, id);
        String sql = "SELECT section_code,metric_code,source_type,source_id,source_local_date,location_label FROM health_report_sources WHERE report_id=?";
        java.util.ArrayList<Object> args = new java.util.ArrayList<>(); args.add(id);
        if (section != null && !section.isBlank()) { sql += " AND section_code=?"; args.add(section); }
        if (metric != null && !metric.isBlank()) { sql += " AND metric_code=?"; args.add(metric); }
        sql += " ORDER BY source_local_date, source_type, source_id";
        return jdbc.query(sql, (rs, n) -> new ReportDtos.SourceResponse(rs.getString(1), rs.getString(2), rs.getString(3),
                rs.getString(4), rs.getDate(5) == null ? null : rs.getDate(5).toLocalDate(), rs.getString(6)), args.toArray());
    }

    @Transactional
    public ReportDtos.DeleteResponse delete(String userId, String id) {
        List<Row> any = rows("WHERE id=? AND user_id=?", id, userId);
        if (any.isEmpty()) throw notFound();
        if (any.get(0).deletedAt != null) return new ReportDtos.DeleteResponse(id, true);
        jdbc.update("UPDATE health_reports SET deleted_at=? WHERE id=? AND user_id=? AND deleted_at IS NULL",
                Timestamp.from(clock.instant()), id, userId);
        return new ReportDtos.DeleteResponse(id, true);
    }

    Row owned(String userId, String id) {
        List<Row> rows = rows("WHERE id=? AND user_id=? AND deleted_at IS NULL", id, userId);
        if (rows.isEmpty()) throw notFound(); return rows.get(0);
    }

    private boolean changed(String userId, Row row) {
        try {
            ReportDtos.Period period = periods.resolve(row.type, row.start, row.timezone);
            return !row.inputHash.equals(hash(collector.collect(userId, period)));
        } catch (RuntimeException exception) {
            return true;
        }
    }

    private boolean isLatest(Row row) {
        Integer value = jdbc.queryForObject("SELECT MAX(version) FROM health_reports WHERE user_id=? AND report_type=? AND period_start=? AND deleted_at IS NULL",
                Integer.class, row.userId, row.type, Date.valueOf(row.start));
        return value != null && value == row.version;
    }

    private ReportDtos.ReportResponse response(Row row, boolean created, boolean changed) {
        return new ReportDtos.ReportResponse(row.id, row.type, row.start, row.end, row.timezone, row.status, row.version,
                isLatest(row), created, changed, row.createdAt, row.snapshot);
    }

    private String hash(ReportDtos.Facts facts) {
        Map<String, Object> canonical = new LinkedHashMap<>();
        canonical.put("type", facts.period().type()); canonical.put("start", facts.period().start());
        canonical.put("end", facts.period().end()); canonical.put("timezone", facts.period().timezone());
        canonical.put("status", facts.period().status()); canonical.put("eligibleDays", facts.period().eligibleDays());
        canonical.put("planState", facts.planState()); canonical.put("planVersion", facts.planVersion());
        canonical.put("targets", facts.targets()); canonical.put("metrics", facts.metrics()); canonical.put("sources", facts.sources());
        try { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(json.writeValueAsBytes(canonical))); }
        catch (Exception exception) { throw new IllegalStateException("无法生成报告摘要", exception); }
    }

    private List<Row> rows(String where, Object... args) {
        return jdbc.query("SELECT id,user_id,report_type,period_start,period_end,timezone,period_status,version,data_cutoff_at,input_hash,snapshot_json,idempotency_key,deleted_at,created_at FROM health_reports " + where,
                (rs, n) -> new Row(rs.getString(1), rs.getString(2), rs.getString(3), rs.getDate(4).toLocalDate(), rs.getDate(5).toLocalDate(),
                        rs.getString(6), rs.getString(7), rs.getInt(8), rs.getTimestamp(9).toInstant(), rs.getString(10), json.readTree(rs.getString(11)),
                        rs.getString(12), rs.getTimestamp(13) == null ? null : rs.getTimestamp(13).toInstant(), rs.getTimestamp(14).toInstant()), args);
    }

    private void ensureUser(String userId) { if (jdbc.queryForObject("SELECT COUNT(*) FROM users WHERE id=?", Integer.class, userId) == 0) throw notFound(); }
    private void ensureProfile(String userId) {
        if (jdbc.queryForObject("SELECT COUNT(*) FROM health_profiles WHERE user_id=? AND completed=TRUE", Integer.class, userId) == 0)
            throw new ApiException(HttpStatus.CONFLICT, "PROFILE_INCOMPLETE", "请先完成健康档案");
    }
    private void validateKey(String key) { if (key == null || key.isBlank()) throw invalid("Idempotency-Key", "生成报告需要 Idempotency-Key"); if (key.trim().length() > 100) throw invalid("Idempotency-Key", "Idempotency-Key 最多 100 个字符"); }
    private ApiException invalid(String field, String message) { return new ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_FAILED", message, List.of(new ApiFieldError(field, message))); }
    private ApiException notFound() { return new ApiException(HttpStatus.NOT_FOUND, "REPORT_NOT_FOUND", "报告不存在或无权访问"); }

    record Row(String id, String userId, String type, LocalDate start, LocalDate end, String timezone, String status,
               int version, Instant cutoff, String inputHash, JsonNode snapshot, String idempotencyKey,
               Instant deletedAt, Instant createdAt) {}
}
