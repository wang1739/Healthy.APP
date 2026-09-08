package com.lightbite.healthy.nutrition;

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
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/nutrition")
public class NutritionController {

    private final NutritionService service;

    public NutritionController(NutritionService service) {
        this.service = service;
    }

    @GetMapping("/days/{date}")
    NutritionDtos.DayResponse day(Authentication authentication, @PathVariable LocalDate date) {
        return service.day(authentication.getName(), date);
    }

    @PostMapping("/entries")
    @ResponseStatus(HttpStatus.CREATED)
    NutritionDtos.DayResponse create(
            Authentication authentication,
            @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
            @RequestBody NutritionDtos.EntryRequest request
    ) {
        return service.create(authentication.getName(), idempotencyKey, request);
    }

    @PutMapping("/entries/{id}")
    NutritionDtos.DayResponse update(
            Authentication authentication,
            @PathVariable String id,
            @RequestBody NutritionDtos.EntryRequest request
    ) {
        return service.update(authentication.getName(), id, request);
    }

    @DeleteMapping("/entries/{id}")
    NutritionDtos.DayResponse delete(Authentication authentication, @PathVariable String id) {
        return service.delete(authentication.getName(), id);
    }
}
