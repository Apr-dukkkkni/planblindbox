package com.planblindbox.mod.auth;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

@RestController @RequestMapping("/api/v1/auth")
public class AuthController {
    public record Register(String username,String email,String password,String gender) {}
    public record Login(String email,String password) {}
    private final AuthService auth;
    public AuthController(AuthService auth){this.auth=auth;}
    @PostMapping("/register") ResponseEntity<AuthService.Profile> register(@RequestBody Register r) {
        return ResponseEntity.status(HttpStatus.CREATED).body(auth.register(r.username(),r.email(),r.password(),r.gender()));
    }
    @PostMapping("/login") AuthService.LoginResponse login(@RequestBody Login r) {
        return auth.login(r.email(),r.password());
    }
    @PostMapping("/logout") @ResponseStatus(HttpStatus.NO_CONTENT)
    void logout(@AuthenticationPrincipal Jwt jwt) {auth.logout(Long.parseLong(jwt.getSubject()));}
}
