package com.lightbite.healthy.datarights;

import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Pattern;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

public final class HealthDataDeletionDtos {
    private HealthDataDeletionDtos() {}

    public record Selection(@NotEmpty(message = "请选择要删除的数据") List<String> dataTypes,
                            LocalDate fromDate, LocalDate toDate) {}
    public record DeleteRequest(@NotEmpty(message = "请选择要删除的数据") List<String> dataTypes,
                                LocalDate fromDate, LocalDate toDate,
                                @Pattern(regexp = "^\\d{6}$", message = "验证码必须为 6 位数字") String code) {}
    public record Impact(Map<String, Integer> recordCounts, int affectedReports, int affectedPlanVersions,
                         String warning) {}
    public record Result(String jobId, String status, Impact deletedImpact) {}
}
