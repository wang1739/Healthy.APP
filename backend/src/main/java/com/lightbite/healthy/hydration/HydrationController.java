package com.lightbite.healthy.hydration;

import java.time.LocalDate;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/hydration")
public class HydrationController {

    private final HydrationService service;

    public HydrationController(HydrationService service) {
        this.service = service;
    }

    @GetMapping("/settings")
    HydrationDtos.SettingsResponse settings(Authentication authentication) {
        return service.settings(authentication.getName());
    }

    @PutMapping("/settings")
    HydrationDtos.SettingsResponse updateSettings(
            Authentication authentication, @RequestBody HydrationDtos.SettingsRequest request
    ) {
        return service.updateSettings(authentication.getName(), request);
    }

    @PostMapping("/settings/adopt-plan-target")
    HydrationDtos.SettingsResponse adoptPlanTarget(Authentication authentication) {
        return service.adoptPlanTarget(authentication.getName());
    }

    @GetMapping("/days/{date}")
    HydrationDtos.DayResponse day(
            Authentication authentication,
            @PathVariable LocalDate date,
            @RequestParam String timezone
    ) {
        return service.day(authentication.getName(), date, timezone);
    }

    @PostMapping("/entries")
    @ResponseStatus(HttpStatus.CREATED)
    HydrationDtos.DayResponse create(
            Authentication authentication,
            @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
            @RequestBody HydrationDtos.EntryRequest request
    ) {
        return service.create(authentication.getName(), idempotencyKey, request);
    }

    @DeleteMapping("/entries/{id}")
    HydrationDtos.DayResponse delete(
            Authentication authentication,
            @PathVariable String id,
            @RequestParam String timezone
    ) {
        return service.delete(authentication.getName(), id, timezone);
    }
}
