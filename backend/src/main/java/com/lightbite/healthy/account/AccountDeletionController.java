package com.lightbite.healthy.account;

import com.lightbite.healthy.auth.AuthDtos;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/account/deletion")
public class AccountDeletionController {
    private final AccountDeletionService deletion;
    public AccountDeletionController(AccountDeletionService deletion) { this.deletion = deletion; }

    @PostMapping
    AccountDeletionService.Status request(@Valid @RequestBody AuthDtos.VerificationRequest request,
                                          Authentication authentication) {
        return deletion.request(authentication.getName(), request.code());
    }
    @GetMapping
    AccountDeletionService.Status status(Authentication authentication) { return deletion.status(authentication.getName()); }
    @PostMapping("/recover")
    ResponseEntity<Void> recover(@Valid @RequestBody AuthDtos.VerificationRequest request,
                                 Authentication authentication) {
        deletion.recover(authentication.getName(), request.code()); return ResponseEntity.noContent().build();
    }
}
