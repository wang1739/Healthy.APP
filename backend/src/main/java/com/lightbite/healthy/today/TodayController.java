package com.lightbite.healthy.today;

import java.time.LocalDate;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/today")
public class TodayController {

    private final TodayService service;

    public TodayController(TodayService service) {
        this.service = service;
    }

    @GetMapping
    TodayDtos.TodayResponse today(
            Authentication authentication,
            @RequestParam LocalDate date
    ) {
        return service.get(authentication.getName(), date);
    }
}
