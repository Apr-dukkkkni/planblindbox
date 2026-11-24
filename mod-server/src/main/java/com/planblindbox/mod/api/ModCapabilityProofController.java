package com.planblindbox.mod.api;

import com.planblindbox.mod.proof.ModCapabilityProofService;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
public class ModCapabilityProofController {
    private final ModCapabilityProofService proofs;

    public ModCapabilityProofController(ModCapabilityProofService proofs) { this.proofs = proofs; }

    @PostMapping("/api/v1/me/mods/{id:.+}/versions/{version}/capabilities/{capability}/proof")
    public Map<String, Object> issue(@AuthenticationPrincipal Jwt jwt,
            @PathVariable String id, @PathVariable String version, @PathVariable String capability) {
        return proofs.issue(Long.parseLong(jwt.getSubject()), id, version, capability);
    }

    @GetMapping("/api/v1/mod-platform/keys/{keyId}")
    public Map<String, Object> publicKey(@PathVariable String keyId) {
        return proofs.publicKey(keyId);
    }
}
