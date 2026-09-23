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
    private static final Set<String> TYPES = Set.of("PROFILE", "MEASUREMENTS", "NUTRITION", "HYDRATION",
            "ACTIVITY", "SLEEP", "TASKS", "PLANS", "REPORTS", "ALL");
    private static final Set<String> SOURCE_TYPES = Set.of("MEASUREMENTS", "NUTRITION", "HYDRATION", "ACTIVITY", "SLEEP");
    private final JdbcTemplate jdbc;
    private final AuthService auth;

    public HealthDataDeletionService(JdbcTemplate jdbc, AuthService auth) { this.jdbc = jdbc; this.auth = auth; }

    public HealthDataDeletionDtos.Impact preview(String userId, HealthDataDeletionDtos.Selection selection) {
        validate(selection.dataTypes(), selection.fromDate(), selection.toDate());
        List<String> types = expand(selection.dataTypes());
        Map<String, Integer> counts = new LinkedHashMap<>();
        for (String type : types) counts.put(type, count(userId, type, selection.fromDate(), selection.toDate()));
        int reports = affectedReports(userId, types, selection.fromDate(), selection.toDate());
        int plans = affectedPlanVersionIds(userId, types, selection.fromDate(), selection.toDate()).size();
        return new HealthDataDeletionDtos.Impact(counts, reports, plans,
                "删除后无法恢复；包含这些源数据的报告版本也会永久删除");
    }

    @Transactional
    public HealthDataDeletionDtos.Result delete(String userId, HealthDataDeletionDtos.DeleteRequest request) {
        jdbc.queryForObject("SELECT id FROM users WHERE id=? FOR UPDATE", String.class, userId);
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
        if (types.contains("TASKS")) deleteTasks(userId, request.fromDate(), request.toDate());
        if (types.contains("PLANS")) deletePlans(userId, request.fromDate(), request.toDate());
        if (types.contains("PROFILE")) deleteProfile(userId);
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
            if ("REPORTS".equals(type)) {
                reportIds.addAll(jdbc.queryForList("SELECT id FROM health_reports WHERE user_id=?"
                                + rangeClause("period_start", from, to), String.class, params(userId, from, to)));
                continue;
            }
            if (!SOURCE_TYPES.contains(type)) continue;
            Source source = source(type);
            reportIds.addAll(jdbc.queryForList("SELECT DISTINCT s.report_id FROM health_report_sources s "
                            + "JOIN health_reports r ON r.id=s.report_id WHERE r.user_id=? AND s.source_type=? "
                            + "AND s.source_id IN (SELECT id FROM " + source.table() + " WHERE user_id=?"
                            + rangeClause(source.dateColumn(), from, to) + ")", String.class,
                    sourceParams(userId, source.sourceType(), from, to)));
        }
        addReportsForSources(reportIds, userId, "PLAN_VERSION",
                affectedPlanVersionIds(userId, types, from, to));
        addReportsForSources(reportIds, userId, "TASK_INSTANCE",
                affectedTaskInstanceIds(userId, types, from, to));
        return reportIds;
    }

    private void addReportsForSources(
            Set<String> reportIds, String userId, String sourceType, Set<String> sourceIds
    ) {
        if (sourceIds.isEmpty()) return;
        String placeholders = String.join(",", java.util.Collections.nCopies(sourceIds.size(), "?"));
        java.util.ArrayList<Object> parameters = new java.util.ArrayList<>();
        parameters.add(userId);
        parameters.add(sourceType);
        parameters.addAll(sourceIds);
        reportIds.addAll(jdbc.queryForList("SELECT DISTINCT s.report_id FROM health_report_sources s "
                        + "JOIN health_reports r ON r.id=s.report_id WHERE r.user_id=? AND s.source_type=? "
                        + "AND s.source_id IN (" + placeholders + ")",
                String.class, parameters.toArray()));
    }

    private int affectedReports(String userId, List<String> types, LocalDate from, LocalDate to) {
        return affectedReportIds(userId, types, from, to).size();
    }

    private Set<String> affectedPlanVersionIds(String userId, List<String> types, LocalDate from, LocalDate to) {
        List<VersionRef> selected = selectedPlanVersions(userId, types, from, to);
        Set<String> versionIds = new LinkedHashSet<>();
        Set<String> planIds = new LinkedHashSet<>();
        for (VersionRef version : selected) {
            versionIds.add(version.id());
            planIds.add(version.planId());
        }
        for (String planId : planIds) {
            versionIds.addAll(jdbc.queryForList("SELECT v.id FROM health_plan_versions v "
                            + "JOIN health_plans p ON p.id=v.plan_id "
                            + "WHERE p.user_id=? AND v.plan_id=? AND v.status='PREVIEW'",
                    String.class, userId, planId));
        }
        return versionIds;
    }

    private Set<String> affectedTaskInstanceIds(String userId, List<String> types, LocalDate from, LocalDate to) {
        Set<String> instanceIds = new LinkedHashSet<>();
        if (types.contains("TASKS")) {
            instanceIds.addAll(jdbc.queryForList("SELECT id FROM task_instances WHERE user_id=?"
                            + rangeClause("original_local_date", from, to),
                    String.class, params(userId, from, to)));
        }
        for (String planId : plansRemovedBySelection(userId, types, from, to)) {
            instanceIds.addAll(jdbc.queryForList("SELECT i.id FROM task_instances i "
                            + "JOIN task_templates t ON t.id=i.template_id "
                            + "WHERE i.user_id=? AND t.user_id=? AND t.plan_id=?",
                    String.class, userId, userId, planId));
        }
        return instanceIds;
    }

    private Set<String> plansRemovedBySelection(String userId, List<String> types, LocalDate from, LocalDate to) {
        if (types.contains("PROFILE") || (types.contains("PLANS") && from == null && to == null)) {
            return new LinkedHashSet<>(jdbc.queryForList(
                    "SELECT id FROM health_plans WHERE user_id=?", String.class, userId));
        }
        List<VersionRef> selected = selectedPlanVersions(userId, types, from, to);
        Set<String> selectedIds = new LinkedHashSet<>();
        Set<String> planIds = new LinkedHashSet<>();
        for (VersionRef version : selected) {
            selectedIds.add(version.id());
            planIds.add(version.planId());
        }
        Set<String> removed = new LinkedHashSet<>();
        for (String planId : planIds) {
            List<String> committedIds = jdbc.queryForList("SELECT v.id FROM health_plan_versions v "
                            + "JOIN health_plans p ON p.id=v.plan_id "
                            + "WHERE p.user_id=? AND v.plan_id=? AND v.status<>'PREVIEW'",
                    String.class, userId, planId);
            if (selectedIds.containsAll(committedIds)) removed.add(planId);
        }
        return removed;
    }

    private List<VersionRef> selectedPlanVersions(
            String userId, List<String> types, LocalDate from, LocalDate to
    ) {
        Map<String, VersionRef> selected = new LinkedHashMap<>();
        if (types.contains("PROFILE")) {
            addVersions(selected, "SELECT v.id,v.plan_id FROM health_plan_versions v "
                    + "JOIN health_plans p ON p.id=v.plan_id WHERE p.user_id=?", userId);
            return selected.values().stream().toList();
        }
        if (types.contains("MEASUREMENTS")) {
            addVersions(selected, "SELECT v.id,v.plan_id FROM health_plan_versions v "
                            + "JOIN health_plans p ON p.id=v.plan_id WHERE p.user_id=? "
                            + "AND v.source_measurement_id IN (SELECT id FROM body_measurements WHERE user_id=?"
                            + rangeClause("CAST(measured_at AS DATE)", from, to) + ")",
                    measurementVersionParams(userId, from, to));
        }
        if (types.contains("PLANS")) {
            addVersions(selected, "SELECT v.id,v.plan_id FROM health_plan_versions v "
                            + "JOIN health_plans p ON p.id=v.plan_id WHERE p.user_id=?"
                            + rangeClause("v.calculation_date", from, to),
                    params(userId, from, to));
        }
        return selected.values().stream().toList();
    }

    private void addVersions(Map<String, VersionRef> versions, String sql, Object... parameters) {
        jdbc.query(sql, rs -> {
            VersionRef version = new VersionRef(rs.getString("id"), rs.getString("plan_id"));
            versions.put(version.id(), version);
        }, parameters);
    }

    private void deleteMeasurementsAndPlans(String userId, LocalDate from, LocalDate to) {
        List<String> types = List.of("MEASUREMENTS");
        Set<String> plans = new LinkedHashSet<>();
        for (VersionRef version : selectedPlanVersions(userId, types, from, to)) plans.add(version.planId());
        deletePlanVersions(userId, affectedPlanVersionIds(userId, types, from, to));
        for (String planId : plans) repairPlan(userId, planId);
        Object[] parameters = params(userId, from, to);
        jdbc.update("DELETE FROM body_measurements WHERE user_id=?" + rangeClause("CAST(measured_at AS DATE)", from, to), parameters);
    }

    private void deletePlanVersions(String userId, Set<String> versionIds) {
        for (String versionId : versionIds) {
            jdbc.update("DELETE FROM health_plan_versions WHERE id=? "
                    + "AND plan_id IN (SELECT id FROM health_plans WHERE user_id=?)", versionId, userId);
        }
    }

    private void repairPlan(String userId, String planId) {
        jdbc.update("DELETE FROM health_plan_versions WHERE plan_id=? AND status='PREVIEW'", planId);
        Integer latest = jdbc.queryForObject("SELECT MAX(version_number) FROM health_plan_versions "
                        + "WHERE plan_id=? AND status <> 'PREVIEW'",
                Integer.class, planId);
        if (latest != null) {
            jdbc.update("UPDATE health_plan_versions SET status=CASE WHEN version_number=? THEN 'ACTIVE' "
                    + "ELSE 'HISTORY' END WHERE plan_id=? AND status <> 'PREVIEW'", latest, planId);
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
        jdbc.update("DELETE FROM health_plan_versions WHERE plan_id=?", planId);
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

    private void deleteProfile(String userId) {
        deletePlans(userId, null, null);
        jdbc.update("DELETE FROM health_goals WHERE user_id=?", userId);
        jdbc.update("DELETE FROM dietary_preferences WHERE user_id=?", userId);
        jdbc.update("DELETE FROM health_risk_answers WHERE user_id=?", userId);
        jdbc.update("DELETE FROM health_profiles WHERE user_id=?", userId);
    }

    private void deleteTasks(String userId, LocalDate from, LocalDate to) {
        String selected = "SELECT id FROM task_instances WHERE user_id=?" + rangeClause("original_local_date", from, to);
        Object[] parameters = params(userId, from, to);
        jdbc.update("DELETE FROM task_notification_events WHERE task_instance_id IN (" + selected + ")", parameters);
        jdbc.update("DELETE FROM task_operation_keys WHERE instance_id IN (" + selected + ")", parameters);
        jdbc.update("DELETE FROM task_instances WHERE user_id=?" + rangeClause("original_local_date", from, to), parameters);
        if (from == null && to == null) jdbc.update("DELETE FROM task_templates WHERE user_id=?", userId);
    }

    private void deletePlans(String userId, LocalDate from, LocalDate to) {
        if (from == null && to == null) {
            for (String planId : jdbc.queryForList("SELECT id FROM health_plans WHERE user_id=?", String.class, userId)) {
                repairPlanAfterDeletingAllVersions(userId, planId);
            }
            return;
        }
        List<String> types = List.of("PLANS");
        Set<String> planIds = new LinkedHashSet<>();
        for (VersionRef version : selectedPlanVersions(userId, types, from, to)) planIds.add(version.planId());
        deletePlanVersions(userId, affectedPlanVersionIds(userId, types, from, to));
        planIds.forEach(planId -> repairPlan(userId, planId));
    }

    private void repairPlanAfterDeletingAllVersions(String userId, String planId) {
        jdbc.update("DELETE FROM health_plan_versions WHERE plan_id=?", planId);
        repairPlan(userId, planId);
    }

    private int count(String userId, String type, LocalDate from, LocalDate to) {
        if ("PROFILE".equals(type)) return countSql("SELECT COUNT(*) FROM health_profiles WHERE user_id=?", userId);
        if ("TASKS".equals(type)) return countSql("SELECT COUNT(*) FROM task_instances WHERE user_id=?"
                + rangeClause("original_local_date", from, to), params(userId, from, to));
        if ("PLANS".equals(type)) return countSql("SELECT COUNT(*) FROM health_plan_versions v JOIN health_plans p ON p.id=v.plan_id WHERE p.user_id=?"
                + rangeClause("v.calculation_date", from, to), params(userId, from, to));
        if ("REPORTS".equals(type)) return countSql("SELECT COUNT(*) FROM health_reports WHERE user_id=?"
                + rangeClause("period_start", from, to), params(userId, from, to));
        Source source = source(type);
        return jdbc.queryForObject("SELECT COUNT(*) FROM " + source.table() + " WHERE user_id=?"
                + rangeClause(source.dateColumn(), from, to), Integer.class, params(userId, from, to));
    }

    private void deleteRange(String table, String dateColumn, String userId, LocalDate from, LocalDate to) {
        jdbc.update("DELETE FROM " + table + " WHERE user_id=?" + rangeClause(dateColumn, from, to), params(userId, from, to));
    }

    private List<String> expand(List<String> requested) {
        return requested.contains("ALL") ? List.of("PROFILE", "MEASUREMENTS", "NUTRITION", "HYDRATION", "ACTIVITY",
                "SLEEP", "TASKS", "PLANS", "REPORTS")
                : requested.stream().distinct().toList();
    }

    private int countSql(String sql, Object... parameters) {
        Integer value = jdbc.queryForObject(sql, Integer.class, parameters);
        return value == null ? 0 : value;
    }

    private void validate(List<String> types, LocalDate from, LocalDate to) {
        if (types == null || types.isEmpty() || types.stream().anyMatch(type -> !TYPES.contains(type)))
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_HEALTH_DATA_TYPE", "删除的数据类型不正确");
        if (from != null && to != null && from.isAfter(to))
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_DATE_RANGE", "开始日期不能晚于结束日期");
    }

    private String rangeClause(String column, LocalDate from, LocalDate to) {
        return (from == null ? "" : " AND " + column + ">=?") + (to == null ? "" : " AND " + column + "<=?");
    }

    private Object[] params(String userId, LocalDate from, LocalDate to) {
        java.util.ArrayList<Object> values = new java.util.ArrayList<>(); values.add(userId);
        if (from != null) values.add(Date.valueOf(from)); if (to != null) values.add(Date.valueOf(to)); return values.toArray();
    }

    private Object[] sourceParams(String userId, String sourceType, LocalDate from, LocalDate to) {
        java.util.ArrayList<Object> values = new java.util.ArrayList<>(); values.add(userId); values.add(sourceType); values.add(userId);
        if (from != null) values.add(Date.valueOf(from)); if (to != null) values.add(Date.valueOf(to)); return values.toArray();
    }

    private Object[] measurementVersionParams(String userId, LocalDate from, LocalDate to) {
        java.util.ArrayList<Object> values = new java.util.ArrayList<>(); values.add(userId); values.add(userId);
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
    private record VersionRef(String id, String planId) {}
}
