package com.planblindbox.mod.api;

import com.planblindbox.mod.proof.ModCapabilityProofService;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
public class ModCapabilityProofController {
    private final ModCapabilityProofService proofs;

    public ModCapabilityProofController(ModCapabilityProofService proofs) { this.proofs = proofs; }

    @PostMapping("/api/v1/me/mods/{id:.+}/versions/{version}/capabilities/{capability}/proof")
    public ResponseEntity<Map<String, Object>> issue(@AuthenticationPrincipal Jwt jwt,
            @PathVariable String id, @PathVariable String version, @PathVariable String capability) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .body(proofs.issue(Long.parseLong(jwt.getSubject()), id, version, capability));
    }

    public record VerifyProofRequest(String token, String modId, String version, String capability) {}

    @PostMapping("/api/v1/me/mod-capability-proofs/verify")
    public ResponseEntity<Map<String, Object>> verify(@AuthenticationPrincipal Jwt jwt,
            @RequestBody VerifyProofRequest request) {
        if (request == null || request.token() == null || request.modId() == null
                || request.version() == null || request.capability() == null) {
            throw new org.springframework.web.server.ResponseStatusException(
                    org.springframework.http.HttpStatus.BAD_REQUEST, "token、modId、version 和 capability 均为必填项");
        }
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .body(proofs.verify(Long.parseLong(jwt.getSubject()), request.token(),
                        request.modId(), request.version(), request.capability()));
    }

    @GetMapping("/api/v1/mod-platform/keys")
    public ResponseEntity<Map<String, Object>> publicKeys() {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(proofs.publicKeys());
    }

    @GetMapping("/api/v1/mod-platform/keys/{keyId}")
    public ResponseEntity<Map<String, Object>> publicKey(@PathVariable String keyId) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(proofs.publicKey(keyId));
    }
}
