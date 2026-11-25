package com.planblindbox.mod.proof;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;
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

    /** Verify a compact JWS, including its key lifecycle and all registered JWT time/audience claims. */
    public Map<String, Object> verify(String token) {
        if (token == null || token.isBlank() || token.length() > 16_384) {
            throw invalidProof("授权证明缺失或长度不合法");
        }
        try {
            String[] parts = token.split("\\.", -1);
            if (parts.length != 3 || parts[0].isEmpty() || parts[1].isEmpty() || parts[2].isEmpty()) {
                throw invalidProof("授权证明格式无效");
            }
            JsonNode header = mapper.readTree(Base64.getUrlDecoder().decode(parts[0]));
            if (header == null || !header.isObject()
                    || !"EdDSA".equals(header.path("alg").asText())
                    || !"JWT".equals(header.path("typ").asText())
                    || header.has("crit") || header.has("jku") || header.has("jwk") || header.has("x5u")) {
                throw invalidProof("授权证明签名头不受支持");
            }
            String keyId = header.path("kid").asText("");
            if (!keyId.matches("[0-9a-f]{64}")) throw invalidProof("授权证明 kid 无效");
            byte[] signature = Base64.getUrlDecoder().decode(parts[2]);
            if (signature.length != 64) throw invalidProof("授权证明签名长度无效");
            byte[] signingInput = (parts[0] + "." + parts[1]).getBytes(StandardCharsets.US_ASCII);
            if (!key.verify(keyId, signingInput, signature)) {
                throw invalidProof("授权证明签名无效或签名密钥已吊销");
            }

            JsonNode payload = mapper.readTree(Base64.getUrlDecoder().decode(parts[1]));
            if (payload == null || !payload.isObject()
                    || !issuer.equals(payload.path("iss").asText())
                    || !"planblindbox-mod-capability".equals(payload.path("aud").asText())
                    || !"MOD_CAPABILITY_AUTHORIZATION".equals(payload.path("proofType").asText())) {
                throw invalidProof("授权证明发行者、受众或类型不匹配");
            }
            long issuedAt = requiredLong(payload, "iat");
            long notBefore = requiredLong(payload, "nbf");
            long expiresAt = requiredLong(payload, "exp");
            long now = Instant.now().getEpochSecond();
            if (issuedAt > now + 30 || notBefore > now || expiresAt <= now
                    || expiresAt <= issuedAt || expiresAt - issuedAt > 900) {
                throw invalidProof("授权证明尚未生效、已经过期或时间范围无效");
            }
            if (!payload.path("jti").isTextual() || payload.path("jti").asText().isBlank()) {
                throw invalidProof("授权证明缺少 jti");
            }
            return mapper.convertValue(payload, new TypeReference<Map<String, Object>>() {});
        } catch (ResponseStatusException e) {
            throw e;
        } catch (Exception e) {
            throw invalidProof("授权证明无法解析或验证");
        }
    }

    private static long requiredLong(JsonNode payload, String name) {
        JsonNode value = payload.get(name);
        if (value == null || !value.isIntegralNumber() || !value.canConvertToLong()) {
            throw invalidProof("授权证明时间字段无效: " + name);
        }
        return value.longValue();
    }

    private static ResponseStatusException invalidProof(String message) {
        return new ResponseStatusException(HttpStatus.UNAUTHORIZED, message);
    }

    public Map<String, Object> publicKey(String keyId) { return key.publicMetadata(keyId); }

    public Map<String, Object> publicKeys() { return key.publicKeys(); }

    private static String base64Url(byte[] value) {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(value);
    }

    public record IssuedProof(String token, String keyId, long issuedAt, long expiresAt) {}
}
