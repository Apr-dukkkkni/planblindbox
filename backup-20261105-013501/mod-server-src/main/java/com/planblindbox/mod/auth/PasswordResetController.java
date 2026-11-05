package com.planblindbox.mod.auth;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

@RestController @RequestMapping("/api/v1/auth/password")
public class PasswordResetController {
    public record Forgot(String email) {}
    public record Reset(String email,String challengeId,String code,String newPassword) {}
    private final PasswordResetService service;
    public PasswordResetController(PasswordResetService service){this.service=service;}
    @PostMapping("/forgot") @ResponseStatus(HttpStatus.ACCEPTED)
    PasswordResetService.ChallengeResult forgot(@RequestBody Forgot r,HttpServletRequest request){
        return service.forgot(r.email(),request.getRemoteAddr());
    }
    @PostMapping("/reset") @ResponseStatus(HttpStatus.NO_CONTENT)
    void reset(@RequestBody Reset r){service.reset(r.email(),r.challengeId(),r.code(),r.newPassword());}
}
