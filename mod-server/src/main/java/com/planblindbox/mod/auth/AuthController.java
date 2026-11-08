package com.planblindbox.mod.auth;

import org.springframework.http.HttpStatus;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

/** V1 password-in-request endpoints are intentionally retired by V2. */
@RestController @RequestMapping("/api/v1/auth")
public class AuthController {
    private final AuthService auth;
    public AuthController(AuthService auth){this.auth=auth;}

    @PostMapping("/register")
    void legacyRegister() {
        throw new ResponseStatusException(HttpStatus.GONE,
            "账号认证已升级为 OPAQUE V2，请更新客户端");
    }
    @PostMapping("/login")
    void legacyLogin() {
        throw new ResponseStatusException(HttpStatus.GONE,
            "账号认证已升级为 OPAQUE V2，请更新客户端");
    }
    @PostMapping("/logout") @ResponseStatus(HttpStatus.NO_CONTENT)
    void logout(@AuthenticationPrincipal Jwt jwt) {
        auth.logout(Long.parseLong(jwt.getSubject()));
    }
}
