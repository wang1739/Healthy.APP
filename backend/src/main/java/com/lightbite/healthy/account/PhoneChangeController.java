package com.lightbite.healthy.account;

import com.lightbite.healthy.auth.AuthService;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/account/phone")
public class PhoneChangeController {
    private final PhoneChangeService phones;
    private final AuthService auth;
    public PhoneChangeController(PhoneChangeService phones, AuthService auth) { this.phones = phones; this.auth = auth; }

    @PostMapping("/change")
    ResponseEntity<Void> change(@Valid @RequestBody PhoneChangeDtos.ChangeRequest request,
                                Authentication authentication) {
        phones.change(authentication.getName(), auth.currentDeviceId(authentication.getCredentials().toString()), request);
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/appeals")
    @ResponseStatus(HttpStatus.CREATED)
    PhoneChangeDtos.AppealResponse appeal(@Valid @RequestBody PhoneChangeDtos.AppealRequest request,
                                          Authentication authentication) {
        return phones.appeal(authentication.getName(), request);
    }

    @GetMapping("/appeals")
    List<PhoneChangeDtos.AppealResponse> appeals(Authentication authentication) {
        return phones.appeals(authentication.getName());
    }
}
