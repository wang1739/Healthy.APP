package com.lightbite.healthy.privacy;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/privacy")
public class PrivacyController {
    private final PrivacyService privacy;
    public PrivacyController(PrivacyService privacy) { this.privacy = privacy; }

    @GetMapping
    PrivacyDtos.Center center(Authentication authentication) { return privacy.center(authentication.getName()); }

    @GetMapping("/documents/{type}/{version}")
    PrivacyDtos.Document document(@PathVariable String type, @PathVariable String version) {
        return privacy.document(type, version);
    }

    @PostMapping("/consents")
    ResponseEntity<Void> accept(@RequestBody PrivacyDtos.AcceptRequest request, Authentication authentication) {
        privacy.accept(authentication.getName(), request); return ResponseEntity.noContent().build();
    }

    @PostMapping("/health-authorization/withdraw")
    ResponseEntity<Void> withdraw(Authentication authentication) {
        privacy.revokeHealth(authentication.getName()); return ResponseEntity.noContent().build();
    }
}
