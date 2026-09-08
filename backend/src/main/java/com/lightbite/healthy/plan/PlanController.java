package com.lightbite.healthy.plan;

import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/plans")
public class PlanController {

    private final PlanService service;

    public PlanController(PlanService service) {
        this.service = service;
    }

    @PostMapping("/preview")
    PlanDtos.PlanResultResponse preview(Authentication authentication) {
        return service.preview(authentication.getName());
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    PlanDtos.CurrentResponse create(
            Authentication authentication,
            @Valid @RequestBody(required = false) PlanDtos.ConfirmRequest request
    ) {
        return service.create(authentication.getName(), request);
    }

    @GetMapping("/current")
    PlanDtos.CurrentResponse current(Authentication authentication) {
        return service.current(authentication.getName());
    }

    @GetMapping("/history")
    List<PlanDtos.HistoryResponse> history(
            Authentication authentication,
            @RequestParam(defaultValue = "20") int limit
    ) {
        int safeLimit = Math.max(1, Math.min(100, limit));
        return service.history(authentication.getName(), safeLimit);
    }

    @PostMapping("/{id}/recalculate")
    PlanDtos.CurrentResponse recalculate(
            Authentication authentication,
            @PathVariable String id,
            @Valid @RequestBody PlanDtos.RecalculateRequest request
    ) {
        return service.recalculate(authentication.getName(), id, request);
    }

    @PutMapping("/{id}/targets")
    PlanDtos.CurrentResponse updateTargets(
            Authentication authentication,
            @PathVariable String id,
            @Valid @RequestBody PlanDtos.UpdateTargetsRequest request
    ) {
        return service.updateTargets(authentication.getName(), id, request);
    }

    @PostMapping("/{id}/pause")
    PlanDtos.CurrentResponse pause(Authentication authentication, @PathVariable String id) {
        return service.pause(authentication.getName(), id);
    }

    @PostMapping("/{id}/resume")
    PlanDtos.CurrentResponse resume(Authentication authentication, @PathVariable String id) {
        return service.resume(authentication.getName(), id);
    }
}
