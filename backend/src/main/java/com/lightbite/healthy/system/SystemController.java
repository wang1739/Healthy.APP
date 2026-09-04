package com.lightbite.healthy.system;

import java.time.Instant;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/system")
public class SystemController {

    @GetMapping("/ping")
    public PingResponse ping() {
        return new PingResponse("ok", "healthy-backend", Instant.now());
    }
}
