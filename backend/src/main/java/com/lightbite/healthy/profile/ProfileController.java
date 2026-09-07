package com.lightbite.healthy.profile;

import jakarta.validation.Valid;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/profile")
public class ProfileController {

    private final ProfileService profileService;

    public ProfileController(ProfileService profileService) {
        this.profileService = profileService;
    }

    @GetMapping
    Map<String, Object> profile(Authentication authentication) {
        return profileService.profile(authentication.getName());
    }

    @PutMapping
    ProfileDtos.CompletenessResponse saveProfile(
            Authentication authentication,
            @Valid @RequestBody ProfileDtos.ProfileRequest request
    ) {
        return profileService.saveProfile(authentication.getName(), request);
    }

    @PostMapping("/measurements")
    @ResponseStatus(HttpStatus.CREATED)
    ProfileDtos.MeasurementResponse addMeasurement(
            Authentication authentication,
            @Valid @RequestBody ProfileDtos.MeasurementRequest request
    ) {
        return profileService.addMeasurement(authentication.getName(), request);
    }

    @GetMapping("/measurements")
    List<ProfileDtos.MeasurementResponse> measurements(Authentication authentication) {
        return profileService.measurements(authentication.getName());
    }

    @PutMapping("/preferences")
    void savePreferences(
            Authentication authentication,
            @Valid @RequestBody ProfileDtos.PreferencesRequest request
    ) {
        profileService.savePreferences(authentication.getName(), request);
    }

    @PostMapping("/risk-assessment")
    ProfileDtos.RiskResponse saveRisk(
            Authentication authentication,
            @Valid @RequestBody ProfileDtos.RiskRequest request
    ) {
        return profileService.saveRisk(authentication.getName(), request);
    }

    @GetMapping("/completeness")
    ProfileDtos.CompletenessResponse completeness(Authentication authentication) {
        return profileService.completeness(authentication.getName());
    }
}
