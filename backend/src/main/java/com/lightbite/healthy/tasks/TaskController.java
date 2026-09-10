package com.lightbite.healthy.tasks;

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
@RequestMapping("/api/v1/tasks")
public class TaskController {
    private final TaskService service;

    public TaskController(TaskService service) {
        this.service = service;
    }

    @GetMapping("/days/{date}")
    TaskDtos.DayResponse day(Authentication authentication, @PathVariable LocalDate date,
                             @RequestParam String timezone) {
        return service.day(authentication.getName(), date, timezone);
    }

    @GetMapping("/weeks/{date}")
    TaskDtos.WeekResponse week(Authentication authentication, @PathVariable LocalDate date,
                              @RequestParam String timezone) {
        return service.week(authentication.getName(), date, timezone);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    TaskDtos.CreateResponse create(Authentication authentication,
                                   @RequestHeader(value = "Idempotency-Key", required = false) String key,
                                   @RequestBody TaskDtos.CreateRequest request) {
        return service.create(authentication.getName(), key, request);
    }

    @PutMapping("/instances/{id}")
    TaskDtos.InstanceResponse updateInstance(Authentication authentication, @PathVariable String id,
                                              @RequestBody TaskDtos.InstanceUpdateRequest request) {
        return service.updateInstance(authentication.getName(), id, request);
    }

    @PutMapping("/templates/{id}")
    TaskDtos.CreateResponse updateTemplate(Authentication authentication, @PathVariable String id,
                                            @RequestBody TaskDtos.TemplateUpdateRequest request) {
        return service.updateTemplate(authentication.getName(), id, request);
    }

    @PostMapping("/instances/{id}/complete")
    TaskDtos.InstanceResponse complete(Authentication authentication, @PathVariable String id,
                                       @RequestHeader(value = "Idempotency-Key", required = false) String key,
                                       @RequestParam String timezone) {
        return service.complete(authentication.getName(), id, key, timezone);
    }

    @PostMapping("/instances/{id}/reopen")
    TaskDtos.InstanceResponse reopen(Authentication authentication, @PathVariable String id,
                                     @RequestHeader(value = "Idempotency-Key", required = false) String key,
                                     @RequestParam String timezone) {
        return service.reopen(authentication.getName(), id, key, timezone);
    }

    @PostMapping("/instances/{id}/skip")
    TaskDtos.InstanceResponse skip(Authentication authentication, @PathVariable String id,
                                   @RequestHeader(value = "Idempotency-Key", required = false) String key,
                                   @RequestBody TaskDtos.SkipRequest request) {
        return service.skip(authentication.getName(), id, key, request == null ? null : request.reason(),
                request == null ? null : request.timezone());
    }

    @PostMapping("/instances/{id}/postpone")
    TaskDtos.InstanceResponse postpone(Authentication authentication, @PathVariable String id,
                                       @RequestHeader(value = "Idempotency-Key", required = false) String key,
                                       @RequestBody TaskDtos.PostponeRequest request) {
        return service.postpone(authentication.getName(), id, key, request);
    }

    @DeleteMapping("/instances/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void deleteInstance(Authentication authentication, @PathVariable String id, @RequestParam String timezone) {
        service.deleteInstance(authentication.getName(), id, timezone);
    }

    @DeleteMapping("/templates/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void deleteTemplate(Authentication authentication, @PathVariable String id,
                        @RequestParam LocalDate effectiveDate, @RequestParam String timezone) {
        service.deleteTemplate(authentication.getName(), id, effectiveDate, timezone);
    }

    @GetMapping("/settings")
    TaskDtos.SettingsResponse settings(Authentication authentication) {
        return service.settings(authentication.getName());
    }

    @PutMapping("/settings")
    TaskDtos.SettingsResponse updateSettings(Authentication authentication,
                                              @RequestBody TaskDtos.SettingsRequest request) {
        return service.updateSettings(authentication.getName(), request);
    }

    @GetMapping("/notifications")
    List<TaskDtos.NotificationResponse> notifications(Authentication authentication,
                                                       @RequestParam LocalDate from, @RequestParam LocalDate to,
                                                       @RequestParam String timezone) {
        return service.notifications(authentication.getName(), from, to, timezone);
    }

    @PostMapping("/notification-events")
    TaskDtos.NotificationEventsResponse notificationEvents(Authentication authentication,
                                                            @RequestBody TaskDtos.NotificationEventsRequest request) {
        return service.notificationEvents(authentication.getName(), request);
    }

    @PostMapping("/plan-updates/adopt")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void adoptPlanUpdates(Authentication authentication, @RequestBody TaskDtos.AdoptRequest request) {
        service.adoptPlanUpdates(authentication.getName(), request.date(), request.timezone());
    }
}
