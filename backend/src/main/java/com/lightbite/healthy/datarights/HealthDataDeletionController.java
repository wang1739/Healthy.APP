package com.lightbite.healthy.datarights;

import jakarta.validation.Valid;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/health-data-deletion")
public class HealthDataDeletionController {
    private final HealthDataDeletionService deletion;

    public HealthDataDeletionController(HealthDataDeletionService deletion) {
        this.deletion = deletion;
    }

    @PostMapping("/preview")
    HealthDataDeletionDtos.Impact preview(
            @Valid @RequestBody HealthDataDeletionDtos.Selection selection,
            Authentication authentication
    ) {
        return deletion.preview(authentication.getName(), selection);
    }

    @PostMapping
    HealthDataDeletionDtos.Result delete(
            @Valid @RequestBody HealthDataDeletionDtos.DeleteRequest request,
            Authentication authentication
    ) {
        return deletion.delete(authentication.getName(), request);
    }
}
