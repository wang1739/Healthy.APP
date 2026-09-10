package com.lightbite.healthy.report;

import tools.jackson.databind.JsonNode;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

public final class ReportDtos {
    private ReportDtos() {
    }

    public record Period(
            String type,
            LocalDate start,
            LocalDate end,
            LocalDate previousStart,
            LocalDate previousEnd,
            String timezone,
            String status,
            int eligibleDays,
            Instant startInstant,
            Instant endExclusiveInstant,
            Instant queryCutoffAt,
            Instant dataCutoffAt
    ) {
    }

    public record GenerateRequest(String type, LocalDate date, String timezone) {}

    public record Source(String section, String metric, String sourceType, String sourceId,
                         LocalDate localDate, String locationLabel, Instant updatedAt) {}

    public record Facts(Period period, String planState, Integer planVersion,
                        Map<String, Object> targets, Map<String, Object> metrics,
                        List<Source> sources) {}

    public record Section(String code, String title, String sufficiency, String reason,
                          int recordDays, int expectedDays, Map<String, Object> metrics,
                          Map<String, Object> targetComparison,
                          Map<String, Object> previousComparison) {}

    public record Advice(String code, String title, String description,
                         String evidenceMetric, int priority) {}

    public record Snapshot(Map<String, Object> period, String displayName, String conclusion,
                           List<Map<String, Object>> keyMetrics, List<Section> sections,
                           Map<String, Object> completeness, List<Advice> advice,
                           String rulesVersion, Instant dataCutoffAt, String disclaimer) {}

    public record ReportResponse(String id, String type, LocalDate periodStart, LocalDate periodEnd,
                                 String timezone, String periodStatus, int version, boolean latest,
                                 boolean created, boolean sourceDataChanged, Instant createdAt,
                                 JsonNode snapshot) {}

    public record ReportSummary(String id, String type, LocalDate periodStart, LocalDate periodEnd,
                                String timezone, String periodStatus, int version, boolean latest,
                                boolean sourceDataChanged, Instant createdAt, String conclusion) {}

    public record SourceResponse(String section, String metric, String sourceType, String resourceId,
                                 LocalDate localDate, String locationLabel) {}

    public record DeleteResponse(String id, boolean deleted) {}
}
