package com.lightbite.healthy.sleep;

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
@RequestMapping("/api/v1/sleep")
public class SleepController {
    private final SleepService service;

    public SleepController(SleepService service) {
        this.service = service;
    }

    @GetMapping("/days/{date}")
    SleepDtos.DayResponse day(Authentication authentication, @PathVariable LocalDate date,
                              @RequestParam String timezone) {
        return service.day(authentication.getName(), date, timezone);
    }

    @GetMapping("/weeks/{date}")
    SleepDtos.WeekResponse week(Authentication authentication, @PathVariable LocalDate date,
                                @RequestParam String timezone) {
        return service.week(authentication.getName(), date, timezone);
    }

    @PostMapping("/records")
    @ResponseStatus(HttpStatus.CREATED)
    SleepDtos.MutationResponse create(Authentication authentication,
                                      @RequestHeader(value = "Idempotency-Key", required = false) String key,
                                      @RequestBody SleepDtos.RecordRequest request) {
        return service.create(authentication.getName(), key, request);
    }

    @PutMapping("/records/{id}")
    SleepDtos.MutationResponse update(Authentication authentication, @PathVariable String id,
                                      @RequestBody SleepDtos.RecordRequest request) {
        return service.update(authentication.getName(), id, request);
    }

    @DeleteMapping("/records/{id}")
    SleepDtos.MutationResponse delete(Authentication authentication, @PathVariable String id,
                                      @RequestParam String timezone) {
        return service.delete(authentication.getName(), id, timezone);
    }
}
