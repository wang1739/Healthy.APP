package com.lightbite.healthy.account;

import java.time.Instant;

public final class AccountDtos {
    private AccountDtos() {}
    public record AccountResponse(String phone, String maskedPhone, String displayName, String status,
                                  boolean profileComplete, boolean healthAuthorized) {}
    public record DeviceResponse(String id, String name, String system, Instant lastSeenAt,
                                 Instant createdAt, boolean currentDevice) {}
    public record SecurityEventResponse(String type, String deviceName, String result, Instant createdAt) {}
}
