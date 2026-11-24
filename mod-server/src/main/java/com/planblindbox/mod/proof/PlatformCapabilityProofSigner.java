package com.planblindbox.mod.proof;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;

/** Creates compact JWS/JWT tokens using the platform Ed25519 key (alg=EdDSA). */
@Service
public final class PlatformCapabilityProofSigner {
    private final PlatformProofSigningKey key;
    private final ObjectMapper mapper;
    private final String issuer;
    private final long ttlSeconds;

    public PlatformCapabilityProofSigner(PlatformProofSigningKey key, ObjectMapper mapper,
            @Value("${mod.platform-signing.issuer:planblindbox-mod-server}") String issuer,
            @Value("${mod.platform-signing.ttl-seconds:300}") long ttlSeconds) {
        if (issuer == null || issuer.isBlank() || issuer.length() > 200) {
            throw new IllegalArgumentException("平台授权证明 issuer 配置无效");
        }
        if (ttlSeconds < 30 || ttlSeconds > 900) {
            throw new IllegalArgumentException("平台授权证明有效期必须在 30 至 900 秒之间");
        }
        this.key = key;
        this.mapper = mapper;
        this.issuer = issuer;
        this.ttlSeconds = ttlSeconds;
    }

    public IssuedProof issue(Map<String, Object> authorizationClaims) {
        Instant now = Instant.now();
        Map<String, Object> claims = new LinkedHashMap<>();
        claims.putAll(authorizationClaims);
        // Reserved JWT claims are written last and cannot be overridden by caller data.
        claims.put("iss", issuer);
        claims.put("aud", "planblindbox-mod-capability");
        claims.put("iat", now.getEpochSecond());
        claims.put("nbf", now.getEpochSecond());
        claims.put("exp", now.plusSeconds(ttlSeconds).getEpochSecond());
        claims.put("jti", java.util.UUID.randomUUID().toString());
        claims.put("proofType", "MOD_CAPABILITY_AUTHORIZATION");

        try {
            Map<String, Object> header = new LinkedHashMap<>();
            header.put("alg", "EdDSA");
            header.put("typ", "JWT");
            header.put("kid", key.keyId());
            String encodedHeader = base64Url(mapper.writeValueAsBytes(header));
            String encodedPayload = base64Url(mapper.writeValueAsBytes(claims));
            String signingInput = encodedHeader + "." + encodedPayload;
            String token = signingInput + "." + base64Url(key.sign(signingInput.getBytes(StandardCharsets.US_ASCII)));
            return new IssuedProof(token, key.keyId(), now.getEpochSecond(), now.plusSeconds(ttlSeconds).getEpochSecond());
        } catch (com.fasterxml.jackson.core.JsonProcessingException e) {
            throw new IllegalStateException("无法序列化平台授权证明", e);
        }
    }

    public Map<String, Object> publicKey(String keyId) { return key.publicMetadata(keyId); }

    public Map<String, Object> publicKeys() { return key.publicKeys(); }

    private static String base64Url(byte[] value) {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(value);
    }

    public record IssuedProof(String token, String keyId, long issuedAt, long expiresAt) {}
}
