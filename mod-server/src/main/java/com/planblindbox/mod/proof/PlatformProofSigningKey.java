package com.planblindbox.mod.proof;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;

import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.Signature;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.X509EncodedKeySpec;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Collections;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Platform-owned Ed25519 key ring. Private keys are supplied by deployment configuration;
 * public keys and lifecycle states are exposed for client-side JWS verification.
 * This key ring is deliberately independent from Publisher signing keys.
 */
@Component
public final class PlatformProofSigningKey {
    private static final String KEY_PAIR_CHALLENGE = "planblindbox-platform-proof-key-pair-check";

    private final Map<String, KeyMaterial> keys;
    private final KeyMaterial activeKey;

    @Autowired
    public PlatformProofSigningKey(
            @Value("${mod.platform-signing.private-key-pkcs8-base64:}") String legacyPrivateKeyBase64,
            @Value("${mod.platform-signing.public-key-x509-base64:}") String legacyPublicKeyBase64,
            @Value("${mod.platform-signing.key-ring-json:}") String keyRingJson,
            @Value("${mod.platform-signing.active-key-id:}") String configuredActiveKeyId,
            ObjectMapper mapper) {
        String legacyPrivate = clean(legacyPrivateKeyBase64);
        String legacyPublic = clean(legacyPublicKeyBase64);
        String ringJson = clean(keyRingJson);
        String requestedActiveId = clean(configuredActiveKeyId).toLowerCase(Locale.ROOT);

        if (!ringJson.isEmpty()) {
            if (!legacyPrivate.isEmpty() || !legacyPublic.isEmpty()) {
                throw new IllegalStateException(
                        "平台签名密钥环与旧版单密钥配置不能同时使用，请清空旧版 MOD_PLATFORM_SIGNING_*_KEY_* 配置");
            }
            this.keys = Collections.unmodifiableMap(parseKeyRing(ringJson, requestedActiveId, mapper));
            this.activeKey = findActiveKey(this.keys, requestedActiveId);
            return;
        }

        if (legacyPrivate.isEmpty() && legacyPublic.isEmpty()) {
            if (!requestedActiveId.isEmpty()) {
                throw new IllegalStateException("配置了平台 active-key-id，但没有配置平台签名密钥");
            }
            this.keys = Map.of();
            this.activeKey = null;
            return; // Existing deployments continue to start, but proof issuance fails closed.
        }
        if (legacyPrivate.isEmpty() || legacyPublic.isEmpty()) {
            throw new IllegalStateException("平台授权证明 Ed25519 私钥和公钥必须同时配置");
        }

        KeyMaterial material = parseKeyMaterial(legacyPrivate, legacyPublic, "ACTIVE");
        if (!requestedActiveId.isEmpty() && !requestedActiveId.equals(material.keyId())) {
            throw new IllegalStateException("平台 active-key-id 与已配置公钥指纹不匹配");
        }
        this.keys = Map.of(material.keyId(), material);
        this.activeKey = material;
    }

    /** Backward-compatible constructor retained for existing unit tests and callers. */
    public PlatformProofSigningKey(String privateKeyBase64, String publicKeyBase64) {
        this(privateKeyBase64, publicKeyBase64, "", "", new ObjectMapper());
    }

    /** Constructor used by tests to exercise multi-key configuration without a Spring context. */
    public PlatformProofSigningKey(String legacyPrivateKeyBase64, String legacyPublicKeyBase64,
            String keyRingJson, String configuredActiveKeyId) {
        this(legacyPrivateKeyBase64, legacyPublicKeyBase64, keyRingJson, configuredActiveKeyId, new ObjectMapper());
    }


    public boolean isConfigured() {
        return activeKey != null;
    }

    public byte[] sign(byte[] signingInput) {
        requireConfigured();
        try {
            Signature signature = Signature.getInstance("Ed25519");
            signature.initSign(activeKey.privateKey());
            signature.update(signingInput);
            return signature.sign();
        } catch (Exception e) {
            throw new IllegalStateException("平台授权证明签名失败", e);
        }
    }

    /** Returns one public key. VERIFY_ONLY keys remain available for validation of unexpired old proofs. */
    public Map<String, Object> publicMetadata(String requestedKeyId) {
        if (requestedKeyId == null || requestedKeyId.isBlank()) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "平台签名公钥不存在");
        }
        KeyMaterial material = keys.get(requestedKeyId.toLowerCase(Locale.ROOT));
        if (material == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "平台签名公钥不存在");
        }
        if (material.status().equals("REVOKED")) {
            throw new ResponseStatusException(HttpStatus.GONE, "平台签名公钥已紧急吊销");
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("keyId", material.keyId());
        result.put("algorithm", "Ed25519");
        result.put("format", "X.509 SubjectPublicKeyInfo");
        result.put("publicKeyX509Base64", material.publicKeyBase64());
        result.put("status", material.status());
        result.put("canVerify", true);
        result.put("canSign", material.status().equals("ACTIVE"));
        return result;
    }

    /** Public key-set discovery endpoint payload. Revoked entries are listed without usable key material. */
    public Map<String, Object> publicKeys() {
        List<Map<String, Object>> metadata = new ArrayList<>();
        for (KeyMaterial material : keys.values()) {
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("keyId", material.keyId());
            item.put("algorithm", "Ed25519");
            item.put("format", "X.509 SubjectPublicKeyInfo");
            item.put("status", material.status());
            item.put("canVerify", !material.status().equals("REVOKED"));
            item.put("canSign", material.status().equals("ACTIVE"));
            if (!material.status().equals("REVOKED")) {
                item.put("publicKeyX509Base64", material.publicKeyBase64());
            }
            metadata.add(item);
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("activeKeyId", activeKey == null ? null : activeKey.keyId());
        result.put("keys", metadata);
        return result;
    }

    public String keyId() {
        requireConfigured();
        return activeKey.keyId();
    }

    private void requireConfigured() {
        if (!isConfigured()) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                    "服务器尚未配置平台授权证明签名密钥");
        }
    }

    private static LinkedHashMap<String, KeyMaterial> parseKeyRing(
            String json, String requestedActiveId, ObjectMapper mapper) {
        try {
            JsonNode root = mapper.readTree(json);
            if (root == null || !root.isArray() || root.size() == 0) {
                throw new IllegalStateException("平台签名 key-ring-json 必须是非空 JSON 数组");
            }
            LinkedHashMap<String, KeyMaterial> parsed = new LinkedHashMap<>();
            if (root.size() > 32) {
                throw new IllegalStateException("平台签名密钥环最多允许配置 32 把密钥");
            }
            int activeCount = 0;
            for (JsonNode node : root) {
                if (!node.isObject()) {
                    throw new IllegalStateException("平台签名密钥环中的每个条目都必须是 JSON 对象");
                }
                String publicValue = clean(node.path("publicKeyX509Base64").asText(""));
                String privateValue = clean(node.path("privateKeyPkcs8Base64").asText(""));
                String status = clean(node.path("status").asText("VERIFY_ONLY")).toUpperCase(Locale.ROOT);
                if (!List.of("ACTIVE", "VERIFY_ONLY", "REVOKED").contains(status)) {
                    throw new IllegalStateException("平台签名密钥状态只允许 ACTIVE、VERIFY_ONLY 或 REVOKED");
                }
                if (status.equals("ACTIVE")) {
                    activeCount++;
                    if (privateValue.isEmpty()) {
                        throw new IllegalStateException("ACTIVE 平台签名密钥必须配置 Ed25519 私钥");
                    }
                } else if (!privateValue.isEmpty()) {
                    throw new IllegalStateException("VERIFY_ONLY/REVOKED 平台密钥不得配置私钥");
                }
                KeyMaterial material = parseKeyMaterial(privateValue, publicValue, status);
                String declaredId = clean(node.path("keyId").asText("")).toLowerCase(Locale.ROOT);
                if (!declaredId.isEmpty() && !declaredId.equals(material.keyId())) {
                    throw new IllegalStateException("平台签名密钥条目的 keyId 与公钥 SHA-256 指纹不匹配");
                }
                if (parsed.putIfAbsent(material.keyId(), material) != null) {
                    throw new IllegalStateException("平台签名密钥环包含重复的公钥指纹");
                }
            }
            if (activeCount != 1) {
                throw new IllegalStateException("平台签名密钥环必须且只能包含一把 ACTIVE 密钥");
            }
            KeyMaterial active = parsed.values().stream()
                    .filter(item -> item.status().equals("ACTIVE"))
                    .findFirst().orElseThrow();
            if (!requestedActiveId.isEmpty() && !requestedActiveId.equals(active.keyId())) {
                throw new IllegalStateException("平台 active-key-id 与 ACTIVE 密钥的公钥指纹不匹配");
            }
            return parsed;
        } catch (IllegalStateException e) {
            throw e;
        } catch (Exception e) {
            throw new IllegalStateException("平台签名密钥环 JSON 或 Ed25519 密钥配置无效", e);
        }
    }

    private static KeyMaterial findActiveKey(Map<String, KeyMaterial> keys, String requestedActiveId) {
        KeyMaterial active = keys.values().stream()
                .filter(item -> item.status().equals("ACTIVE"))
                .findFirst().orElse(null);
        if (active == null || (!requestedActiveId.isEmpty() && !requestedActiveId.equals(active.keyId()))) {
            throw new IllegalStateException("平台签名密钥环没有匹配的 ACTIVE 密钥");
        }
        return active;
    }

    private static KeyMaterial parseKeyMaterial(String privateValue, String publicValue, String status) {
        if (publicValue == null || publicValue.isBlank()) {
            throw new IllegalStateException("平台 Ed25519 公钥不能为空");
        }
        try {
            byte[] publicBytes = Base64.getDecoder().decode(publicValue);
            KeyFactory factory = KeyFactory.getInstance("Ed25519");
            PublicKey publicKey = factory.generatePublic(new X509EncodedKeySpec(publicBytes));
            PrivateKey privateKey = null;
            if (privateValue != null && !privateValue.isBlank()) {
                byte[] privateBytes = Base64.getDecoder().decode(privateValue);
                privateKey = factory.generatePrivate(new PKCS8EncodedKeySpec(privateBytes));
                verifyKeyPair(privateKey, publicKey);
            }
            String keyId = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(publicBytes));
            return new KeyMaterial(keyId, privateKey, publicKey,
                    Base64.getEncoder().encodeToString(publicBytes), status);
        } catch (IllegalStateException e) {
            throw e;
        } catch (Exception e) {
            throw new IllegalStateException("平台授权证明 Ed25519 密钥配置无效", e);
        }
    }

    private static void verifyKeyPair(PrivateKey privateKey, PublicKey publicKey) throws Exception {
        byte[] challenge = KEY_PAIR_CHALLENGE.getBytes(StandardCharsets.UTF_8);
        Signature signer = Signature.getInstance("Ed25519");
        signer.initSign(privateKey);
        signer.update(challenge);
        byte[] signed = signer.sign();
        Signature verifier = Signature.getInstance("Ed25519");
        verifier.initVerify(publicKey);
        verifier.update(challenge);
        if (!verifier.verify(signed)) {
            throw new IllegalStateException("平台授权证明 Ed25519 公私钥不匹配");
        }
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }

    private record KeyMaterial(String keyId, PrivateKey privateKey, PublicKey publicKey,
            String publicKeyBase64, String status) {}
}
