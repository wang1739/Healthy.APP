package com.lightbite.healthy.account;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.time.Instant;

public final class PhoneChangeDtos {
    private PhoneChangeDtos() {}
    public record ChangeRequest(
            @Pattern(regexp = "^\\d{6}$", message = "旧手机号验证码必须为 6 位数字") String oldCode,
            @Pattern(regexp = "^1[3-9]\\d{9}$", message = "请输入正确的新手机号") String newPhone,
            @Pattern(regexp = "^\\d{6}$", message = "新手机号验证码必须为 6 位数字") String newCode) {}
    public record AppealRequest(
            @Pattern(regexp = "^1[3-9]\\d{9}$", message = "请输入正确的新手机号") String newPhone,
            @NotBlank(message = "请提供申诉材料") @Size(max = 500) String materialReference) {}
    public record AppealResponse(String id, String newPhone, String status, String reason,
                                 Instant createdAt, Instant completedAt) {}
}
