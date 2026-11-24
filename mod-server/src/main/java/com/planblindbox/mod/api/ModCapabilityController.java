package com.planblindbox.mod.api;

import com.planblindbox.mod.service.ModCapabilityAuthorizationService;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/v1/me/mods")
public class ModCapabilityController {
    private final ModCapabilityAuthorizationService service;
    public ModCapabilityController(ModCapabilityAuthorizationService service) { this.service = service; }

    public record GrantRequest(boolean granted) {}

    @GetMapping("/{id:.+}/versions/{version}/capabilities/{capability}")
    public Map<String,Object> status(@AuthenticationPrincipal Jwt jwt,
            @PathVariable String id, @PathVariable String version, @PathVariable String capability) {
        return service.userStatus(Long.parseLong(jwt.getSubject()), id, version, capability);
    }

    @PutMapping("/{id:.+}/versions/{version}/capabilities/{capability}")
    public Map<String,Object> grant(@AuthenticationPrincipal Jwt jwt,
            @PathVariable String id, @PathVariable String version, @PathVariable String capability,
            @RequestBody GrantRequest request) {
        return service.setUserGrant(Long.parseLong(jwt.getSubject()), id, version, capability, request.granted());
    }

    @DeleteMapping("/{id:.+}/versions/{version}/capabilities/{capability}")
    public Map<String,Object> revoke(@AuthenticationPrincipal Jwt jwt,
            @PathVariable String id, @PathVariable String version, @PathVariable String capability) {
        return service.setUserGrant(Long.parseLong(jwt.getSubject()), id, version, capability, false);
    }
}
