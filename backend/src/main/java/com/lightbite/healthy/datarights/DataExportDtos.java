package com.lightbite.healthy.datarights;

import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.time.Instant;

public final class DataExportDtos {
    private DataExportDtos() {}

    public record Request(
            @Pattern(regexp = "^\\d{6}$", message = "验证码必须为 6 位数字") String code,
            @Size(min = 8, max = 32, message = "PDF 密码长度需要为 8 至 32 位") String password) {}

    public record Job(String id, String status, Instant dataCutoffAt, Instant createdAt,
                      Instant completedAt, Instant expiresAt, String failureMessage) {}
}
