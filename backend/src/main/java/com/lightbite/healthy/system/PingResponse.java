package com.lightbite.healthy.system;

import java.time.Instant;

public record PingResponse(String status, String service, Instant timestamp) {
}
