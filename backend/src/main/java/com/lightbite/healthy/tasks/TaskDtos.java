package com.lightbite.healthy.tasks;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;

public final class TaskDtos {
    private TaskDtos() {
    }

    public record CreateRequest(String title, String note, String category, String priority, Boolean allDay,
                                String localTime, LocalDate date, String recurrenceType, Integer weekdaysMask,
                                Integer reminderOffsetMinutes, String timezone) {
    }

    public record InstanceUpdateRequest(String title, String note, String category, String priority, Boolean allDay,
                                        String localTime, Integer reminderOffsetMinutes, Integer expectedVersion,
                                        String timezone) {
    }

    public record TemplateUpdateRequest(String title, String note, String category, String priority, Boolean allDay,
                                        String localTime, String recurrenceType, Integer weekdaysMask,
                                        Integer reminderOffsetMinutes, LocalDate effectiveDate,
                                        Integer expectedVersion, String timezone) {
    }

    public record PostponeRequest(String type, OffsetDateTime customAt, String timezone) {
    }

    public record SkipRequest(String reason, String timezone) {
    }

    public record AdoptRequest(LocalDate date, String timezone) {
    }

    public record SettingsRequest(Boolean quietEnabled, String quietStartTime, String quietEndTime,
                                  Integer expectedVersion) {
    }

    public record NotificationEventRequest(String instanceId, String deviceKeyHash, String eventType,
                                           Instant scheduledFor, Instant occurredAt, String idempotencyKey) {
    }

    public record NotificationEventsRequest(List<NotificationEventRequest> events) {
    }

    public record InstanceResponse(String id, String templateId, String source, String title, String note,
                                   String category, String priority, boolean allDay, String localTime,
                                   Integer reminderOffsetMinutes, LocalDate originalLocalDate,
                                   LocalDate currentLocalDate, Instant originalDueAt, Instant currentDueAt,
                                   String timezone, String status, String completionSource, Instant completedAt,
                                   Instant skippedAt, String skipReason, int postponeCount, boolean overdue,
                                   boolean hasPlanUpdate, int version) {
    }

    public record CreateResponse(String templateId, int version, List<InstanceResponse> instances) {
    }

    public record DaySummary(int totalCount, int completedCount, int pendingCount, int skippedCount,
                             int overdueCount) {
    }

    public record DayResponse(LocalDate date, String status, List<InstanceResponse> timeline,
                              List<InstanceResponse> allDay, List<InstanceResponse> completed,
                              List<InstanceResponse> skipped, DaySummary summary, boolean hasPlanUpdate,
                              String healthGuide) {
    }

    public record CategorySummary(String category, int totalCount, int completedCount) {
    }

    public record WeekResponse(LocalDate startDate, LocalDate endDate, int totalCount, int completedCount,
                               int skippedCount, int postponedCount, int overdueCount, BigDecimal completionRate,
                               int userCompletedCount, int autoCompletedCount,
                               List<CategorySummary> categories) {
    }

    public record SettingsResponse(boolean quietEnabled, String quietStartTime, String quietEndTime, int version) {
    }

    public record NotificationResponse(String instanceId, String title, Instant dueAt, Instant notifyAt,
                                       String timezone, String category, String source) {
    }

    public record NotificationEventsResponse(int acceptedCount) {
    }

    public record NextTask(String id, String title, Instant dueAt, LocalDate date, String category, String source,
                           boolean allDay) {
    }

    public record TodaySummary(String status, int totalCount, int completedCount, int pendingCount,
                               int overdueCount, NextTask nextTask, boolean hasPlanUpdate, String healthGuide) {
    }
}
