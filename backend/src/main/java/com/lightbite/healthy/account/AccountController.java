package com.lightbite.healthy.account;

import com.lightbite.healthy.auth.AuthDtos;
import com.lightbite.healthy.auth.AuthService;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/account")
public class AccountController {
    private final AccountService accounts;
    private final AuthService auth;
    private final SecurityEventService events;

    public AccountController(AccountService accounts, AuthService auth, SecurityEventService events) {
        this.accounts = accounts; this.auth = auth; this.events = events;
    }

    @GetMapping
    AccountDtos.AccountResponse account(Authentication authentication) {
        return accounts.account(authentication.getName());
    }

    @GetMapping("/devices")
    List<AccountDtos.DeviceResponse> devices(Authentication authentication) {
        return accounts.devices(authentication.getName(), device(authentication));
    }

    @DeleteMapping("/devices/{id}")
    ResponseEntity<Void> revokeDevice(@PathVariable String id, Authentication authentication) {
        accounts.revoke(authentication.getName(), device(authentication), id);
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/devices/logout-others")
    ResponseEntity<Void> revokeOthers(@Valid @RequestBody AuthDtos.VerificationRequest request,
                                      Authentication authentication) {
        accounts.revokeOthers(authentication.getName(), device(authentication), request.code());
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/security-events")
    List<AccountDtos.SecurityEventResponse> securityEvents(Authentication authentication) {
        return events.list(authentication.getName());
    }

    private String device(Authentication authentication) {
        return auth.currentDeviceId(authentication.getCredentials().toString());
    }
}
