package com.lightbite.healthy.auth;

import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public final class AuthDtos {

    private AuthDtos() {
    }

    public record SendCodeRequest(
            @Pattern(regexp = "^1[3-9]\\d{9}$", message = "请输入正确的手机号") String phone,
            @NotBlank(message = "验证码用途不能为空") String purpose
    ) {
    }

    public record SendCodeResponse(String message, long expiresInSeconds, String debugCode) {
    }

    public record SmsLoginRequest(
            @Pattern(regexp = "^1[3-9]\\d{9}$", message = "请输入正确的手机号") String phone,
            @Pattern(regexp = "^\\d{6}$", message = "验证码必须为 6 位数字") String code,
            @NotBlank(message = "设备名称不能为空") @Size(max = 100) String deviceName,
            @Size(min = 8, max = 72, message = "密码长度需要为 8 至 72 位") String password,
            @AssertTrue(message = "请先同意用户协议与隐私政策") boolean acceptedTerms
    ) {
    }

    public record PasswordLoginRequest(
            @Pattern(regexp = "^1[3-9]\\d{9}$", message = "请输入正确的手机号") String phone,
            @NotBlank(message = "请输入密码") String password,
            @NotBlank(message = "设备名称不能为空") @Size(max = 100) String deviceName
    ) {
    }

    public record RefreshRequest(@NotBlank(message = "Refresh Token 不能为空") String refreshToken) {
    }

    public record LogoutRequest(boolean allDevices) {
    }

    public record VerificationRequest(
            @Pattern(regexp = "^\\d{6}$", message = "验证码必须为 6 位数字") String code
    ) {
    }

    public record AuthResponse(
            String accessToken,
            String refreshToken,
            long expiresInSeconds,
            boolean profileComplete
    ) {
    }
}
