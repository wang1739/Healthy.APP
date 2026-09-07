package com.lightbite.healthy.auth;

import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {

    private final AuthService authService;

    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    @PostMapping("/sms/send")
    AuthDtos.SendCodeResponse sendCode(@Valid @RequestBody AuthDtos.SendCodeRequest request) {
        return authService.sendCode(request);
    }

    @PostMapping("/sms/login")
    AuthDtos.AuthResponse smsLogin(@Valid @RequestBody AuthDtos.SmsLoginRequest request) {
        return authService.smsLogin(request);
    }

    @PostMapping("/password/login")
    AuthDtos.AuthResponse passwordLogin(@Valid @RequestBody AuthDtos.PasswordLoginRequest request) {
        return authService.passwordLogin(request);
    }

    @PostMapping("/token/refresh")
    AuthDtos.AuthResponse refresh(@Valid @RequestBody AuthDtos.RefreshRequest request) {
        return authService.refresh(request);
    }

    @PostMapping("/logout")
    ResponseEntity<Void> logout(
            Authentication authentication,
            @RequestBody(required = false) AuthDtos.LogoutRequest request
    ) {
        authService.logout(
                authentication.getName(),
                authentication.getCredentials().toString(),
                request != null && request.allDevices()
        );
        return ResponseEntity.noContent().build();
    }
}
