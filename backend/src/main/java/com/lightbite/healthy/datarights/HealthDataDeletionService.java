package com.lightbite.healthy.datarights;

import com.lightbite.healthy.auth.AuthService;
import com.lightbite.healthy.common.api.ApiException;
import java.sql.Date;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class HealthDataDeletionService {
    private static final Set<String> TYPES = Set.of("MEASUREMENTS", "NUTRITION", "HYDRATION", "ACTIVITY", "SLEEP", "ALL");
    private final JdbcTemplate jdbc;
    private final AuthService auth;

    public HealthDataDeletionService(JdbcTemplate jdbc, AuthService auth) { this.jdbc = jdbc; this.auth = auth; }

    public HealthDataDeletionDtos.Impact preview(String userId, HealthDataDeletionDtos.Selection selection) {
        validate(selection.dataTypes(), selection.fromDate(), selection.toDate());
        List<String> types = expand(selection.dataTypes());
        Map<String, Integer> counts = new LinkedHashMap<>();
        for (String type : types) counts.put(type, count(userId, type, selection.fromDate(), selection.toDate()));
        int reports = affectedReports(userId, types, selection.fromDate(), selection.toDate());
        int plans = types.contains("MEASUREMENTS") ? affectedPlans(userId, selection.fromDate(), selection.toDate()) : 0;
        return new HealthDataDeletionDtos.Impact(counts, reports, plans,
                "删除后无法恢复；包含这些源数据的报告版本也会永久删除");
    }

    @Transactional
    public HealthDataDeletionDtos.Result delete(String userId, HealthDataDeletionDtos.DeleteRequest request) {
        HealthDataDeletionDtos.Selection selection = new HealthDataDeletionDtos.Selection(
                request.dataTypes(), request.fromDate(), request.toDate());
        HealthDataDeletionDtos.Impact impact = preview(userId, selection);
        String phone = jdbc.queryForObject("SELECT phone FROM users WHERE id=?", String.class, userId);
        auth.consumeCode(phone, "HEALTH_DATA_DELETE", request.code());
        Integer active = jdbc.queryForObject("SELECT COUNT(*) FROM health_data_deletion_jobs WHERE user_id=? "
                + "AND status IN ('PENDING','PROCESSING')", Integer.class, userId);
        if (active != null && active > 0)
            throw new ApiException(HttpStatus.CONFLICT, "HEALTH_DELETE_ACTIVE", "已有健康数据删除正在处理");
        String id = UUID.randomUUID().toString();
        jdbc.update("INSERT INTO health_data_deletion_jobs (id,user_id,status,selection_json,impact_json) "
                        + "VALUES (?,?,'PROCESSING',?,?)", id, userId, selection.toString(), impact.toString());
        List<String> types = expand(request.dataTypes());
        deleteAffectedReports(userId, types, request.fromDate(), request.toDate());
        if (types.contains("MEASUREMENTS")) deleteMeasurementsAndPlans(userId, request.fromDate(), request.toDate());
        if (types.contains("NUTRITION")) deleteRange("meal_entries", "entry_date", userId, request.fromDate(), request.toDate());
        if (types.contains("HYDRATION")) deleteRange("hydration_entries", "CAST(occurred_at AS DATE)", userId, request.fromDate(), request.toDate());
        if (types.contains("ACTIVITY")) deleteRange("activity_records", "CAST(occurred_at AS DATE)", userId, request.fromDate(), request.toDate());
        if (types.contains("SLEEP")) {
            jdbc.update("DELETE FROM sleep_record_tags WHERE sleep_record_id IN (SELECT id FROM sleep_records WHERE user_id=?"
                    + rangeClause("wake_local_date", request.fromDate(), request.toDate()) + ")", params(userId, request.fromDate(), request.toDate()));
            deleteRange("sleep_records", "wake_local_date", userId, request.fromDate(), request.toDate());
        }
        if (request.dataTypes().contains("ALL")) deleteProfileState(userId);
        jdbc.update("UPDATE health_data_deletion_jobs SET status='COMPLETED',completed_at=CURRENT_TIMESTAMP WHERE id=?", id);
        return new HealthDataDeletionDtos.Result(id, "已完成", impact);
    }

    private void deleteAffectedReports(String userId, List<String> types, LocalDate from, LocalDate to) {
        Set<String> reportIds = affectedReportIds(userId, types, from, to);
        for (String reportId : reportIds) {
            jdbc.update("DELETE FROM health_report_sources WHERE report_id=?", reportId);
            jdbc.update("DELETE FROM health_reports WHERE id=? AND user_id=?", reportId, userId);
        }
    }

    private Set<String> affectedReportIds(String userId, List<String> types, LocalDate from, LocalDate to) {
        Set<String> reportIds = new LinkedHashSet<>();
        for (String type : types) {
            Source source = source(type);
            reportIds.addAll(jdbc.queryForList("SELECT DISTINCT s.report_id FROM health_report_sources s "
                            + "JOIN health_reports r ON r.id=s.report_id WHERE r.user_id=? AND s.source_type=? "
                            + "AND s.source_id IN (SELECT id FROM " + source.table() + " WHERE user_id=?"
                            + rangeClause(source.dateColumn(), from, to) + ")", String.class,
                    sourceParams(userId, source.sourceType(), from, to)));
        }
        return reportIds;
    }

    private int affectedReports(String userId, List<String> types, LocalDate from, LocalDate to) {
        return affectedReportIds(userId, types, from, to).size();
    }

    private void deleteMeasurementsAndPlans(String userId, LocalDate from, LocalDate to) {
        String selected = "SELECT id FROM body_measurements WHERE user_id=?" + rangeClause("CAST(measured_at AS DATE)", from, to);
        Object[] parameters = params(userId, from, to);
        List<String> plans = jdbc.queryForList("SELECT DISTINCT plan_id FROM health_plan_versions "
                + "WHERE source_measurement_id IN (" + selected + ")", String.class, parameters);
        jdbc.update("DELETE FROM health_plan_versions WHERE source_measurement_id IN (" + selected + ")", parameters);
        for (String planId : plans) repairPlan(userId, planId);
        jdbc.update("DELETE FROM body_measurements WHERE user_id=?" + rangeClause("CAST(measured_at AS DATE)", from, to), parameters);
    }

    private void repairPlan(String userId, String planId) {
        Integer latest = jdbc.queryForObject("SELECT MAX(version_number) FROM health_plan_versions WHERE plan_id=?",
                Integer.class, planId);
        if (latest != null) {
            jdbc.update("UPDATE health_plans SET current_version=?,updated_at=CURRENT_TIMESTAMP WHERE id=? AND user_id=?",
                    latest, planId, userId);
            return;
        }
        jdbc.update("DELETE FROM task_notification_events WHERE task_instance_id IN (SELECT i.id FROM task_instances i "
                + "JOIN task_templates t ON t.id=i.template_id WHERE t.plan_id=?)", planId);
        jdbc.update("DELETE FROM task_operation_keys WHERE instance_id IN (SELECT i.id FROM task_instances i "
                + "JOIN task_templates t ON t.id=i.template_id WHERE t.plan_id=?)", planId);
        jdbc.update("DELETE FROM task_instances WHERE template_id IN (SELECT id FROM task_templates WHERE plan_id=?)", planId);
        jdbc.update("DELETE FROM task_templates WHERE plan_id=?", planId);
        jdbc.update("DELETE FROM health_plans WHERE id=? AND user_id=?", planId, userId);
    }

    private void deleteProfileState(String userId) {
        jdbc.update("DELETE FROM task_notification_events WHERE user_id=?", userId);
        jdbc.update("DELETE FROM task_operation_keys WHERE user_id=?", userId);
        jdbc.update("DELETE FROM task_instances WHERE user_id=?", userId);
        jdbc.update("DELETE FROM task_templates WHERE user_id=?", userId);
        jdbc.update("DELETE FROM task_settings WHERE user_id=?", userId);
        jdbc.update("DELETE FROM health_goals WHERE user_id=?", userId);
        jdbc.update("DELETE FROM dietary_preferences WHERE user_id=?", userId);
        jdbc.update("DELETE FROM health_risk_answers WHERE user_id=?", userId);
        jdbc.update("DELETE FROM health_permissions WHERE user_id=?", userId);
        jdbc.update("DELETE FROM health_profiles WHERE user_id=?", userId);
        jdbc.update("DELETE FROM health_plan_versions WHERE plan_id IN (SELECT id FROM health_plans WHERE user_id=?)", userId);
        jdbc.update("DELETE FROM health_plans WHERE user_id=?", userId);
    }

    private int affectedPlans(String userId, LocalDate from, LocalDate to) {
        return jdbc.queryForObject("SELECT COUNT(*) FROM health_plan_versions WHERE source_measurement_id IN "
                + "(SELECT id FROM body_measurements WHERE user_id=?" + rangeClause("CAST(measured_at AS DATE)", from, to) + ")",
                Integer.class, params(userId, from, to));
    }

    private int count(String userId, String type, LocalDate from, LocalDate to) {
        Source source = source(type);
        return jdbc.queryForObject("SELECT COUNT(*) FROM " + source.table() + " WHERE user_id=?"
                + rangeClause(source.dateColumn(), from, to), Integer.class, params(userId, from, to));
    }

    private void deleteRange(String table, String dateColumn, String userId, LocalDate from, LocalDate to) {
        jdbc.update("DELETE FROM " + table + " WHERE user_id=?" + rangeClause(dateColumn, from, to), params(userId, from, to));
    }

    private List<String> expand(List<String> requested) {
        return requested.contains("ALL") ? List.of("MEASUREMENTS", "NUTRITION", "HYDRATION", "ACTIVITY", "SLEEP")
                : requested.stream().distinct().toList();
    }

    private void validate(List<String> types, LocalDate from, LocalDate to) {
        if (types == null || types.isEmpty() || types.stream().anyMatch(type -> !TYPES.contains(type)))
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_HEALTH_DATA_TYPE", "删除的数据类型不正确");
        if (from != null && to != null && from.isAfter(to))
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_DATE_RANGE", "开始日期不能晚于结束日期");
    }

    private String rangeClause(String column, LocalDate from, LocalDate to) {
        return (from == null ? "" : " AND " + column + ">?") + (to == null ? "" : " AND " + column + "<=?");
    }

    private Object[] params(String userId, LocalDate from, LocalDate to) {
        java.util.ArrayList<Object> values = new java.util.ArrayList<>(); values.add(userId);
        if (from != null) values.add(Date.valueOf(from)); if (to != null) values.add(Date.valueOf(to)); return values.toArray();
    }

    private Object[] sourceParams(String userId, String sourceType, LocalDate from, LocalDate to) {
        java.util.ArrayList<Object> values = new java.util.ArrayList<>(); values.add(userId); values.add(sourceType); values.add(userId);
        if (from != null) values.add(Date.valueOf(from)); if (to != null) values.add(Date.valueOf(to)); return values.toArray();
    }

    private Source source(String type) { return switch (type) {
        case "MEASUREMENTS" -> new Source("body_measurements", "CAST(measured_at AS DATE)", "WEIGHT_MEASUREMENT");
        case "NUTRITION" -> new Source("meal_entries", "entry_date", "MEAL_ENTRY");
        case "HYDRATION" -> new Source("hydration_entries", "CAST(occurred_at AS DATE)", "HYDRATION_ENTRY");
        case "ACTIVITY" -> new Source("activity_records", "CAST(occurred_at AS DATE)", "ACTIVITY_RECORD");
        case "SLEEP" -> new Source("sleep_records", "wake_local_date", "SLEEP_RECORD");
        default -> throw new IllegalArgumentException(type);
    }; }
    private record Source(String table, String dateColumn, String sourceType) {}
}
