package com.lightbite.healthy.activity;

import java.time.LocalDate;
import java.util.List;
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
@RequestMapping("/api/v1/activity")
public class ActivityController {

    private final ActivityService service;

    public ActivityController(ActivityService service) {
        this.service = service;
    }

    @GetMapping("/types")
    List<ActivityDtos.TypeResponse> types(
            Authentication authentication,
            @RequestParam(required = false) String query
    ) {
        return service.types(authentication.getName(), query);
    }

    @PostMapping("/types/custom")
    @ResponseStatus(HttpStatus.CREATED)
    ActivityDtos.TypeResponse createCustomType(
            Authentication authentication,
            @RequestBody ActivityDtos.CustomTypeRequest request
    ) {
        return service.createCustomType(authentication.getName(), request);
    }

    @GetMapping("/days/{date}")
    ActivityDtos.DayResponse day(
            Authentication authentication,
            @PathVariable LocalDate date,
            @RequestParam String timezone
    ) {
        return service.day(authentication.getName(), date, timezone);
    }

    @GetMapping("/weeks/{date}")
    ActivityDtos.WeekResponse week(
            Authentication authentication,
            @PathVariable LocalDate date,
            @RequestParam String timezone
    ) {
        return service.week(authentication.getName(), date, timezone);
    }

    @PostMapping("/records")
    @ResponseStatus(HttpStatus.CREATED)
    ActivityDtos.MutationResponse create(
            Authentication authentication,
            @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
            @RequestBody ActivityDtos.RecordRequest request
    ) {
        return service.create(authentication.getName(), idempotencyKey, request);
    }

    @PutMapping("/records/{id}")
    ActivityDtos.MutationResponse update(
            Authentication authentication,
            @PathVariable String id,
            @RequestBody ActivityDtos.RecordRequest request
    ) {
        return service.update(authentication.getName(), id, request);
    }

    @DeleteMapping("/records/{id}")
    ActivityDtos.MutationResponse delete(
            Authentication authentication,
            @PathVariable String id,
            @RequestParam String timezone
    ) {
        return service.delete(authentication.getName(), id, timezone);
    }
}
