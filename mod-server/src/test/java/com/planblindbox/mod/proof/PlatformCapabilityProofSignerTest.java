package com.planblindbox.mod.proof;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.MessageDigest;
import java.security.Signature;
import java.security.spec.X509EncodedKeySpec;
import java.util.Base64;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class PlatformCapabilityProofSignerTest {
    private static final ObjectMapper MAPPER = new ObjectMapper();

    private static PlatformProofSigningKey key(KeyPair pair) {
        return new PlatformProofSigningKey(
                Base64.getEncoder().encodeToString(pair.getPrivate().getEncoded()),
                Base64.getEncoder().encodeToString(pair.getPublic().getEncoded()));
    }

    private static String publicBase64(KeyPair pair) {
        return Base64.getEncoder().encodeToString(pair.getPublic().getEncoded());
    }

    private static String privateBase64(KeyPair pair) {
        return Base64.getEncoder().encodeToString(pair.getPrivate().getEncoded());
    }

    private static String keyId(KeyPair pair) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                .digest(pair.getPublic().getEncoded()));
    }

    private static Map<String, Object> keyEntry(KeyPair pair, String status, boolean includePrivate) {
        Map<String, Object> entry = new LinkedHashMap<>();
        entry.put("keyId", keyIdUnchecked(pair));
        entry.put("publicKeyX509Base64", publicBase64(pair));
        entry.put("status", status);
        if (includePrivate) entry.put("privateKeyPkcs8Base64", privateBase64(pair));
        return entry;
    }

    private static String keyIdUnchecked(KeyPair pair) {
        try { return keyId(pair); }
        catch (Exception e) { throw new IllegalStateException(e); }
    }

    private static String keyRingJson(List<Map<String, Object>> entries) throws Exception {
        return MAPPER.writeValueAsString(entries);
    }

    private static JsonNode decodePart(String token, int index) throws Exception {
        String[] parts = token.split("\\.");
        return MAPPER.readTree(Base64.getUrlDecoder().decode(parts[index]));
    }

    private static boolean verifies(String token, String publicKeyBase64) throws Exception {
        String[] parts = token.split("\\.");
        var publicKey = KeyFactory.getInstance("Ed25519").generatePublic(
                new X509EncodedKeySpec(Base64.getDecoder().decode(publicKeyBase64)));
        Signature verifier = Signature.getInstance("Ed25519");
        verifier.initVerify(publicKey);
        verifier.update((parts[0] + "." + parts[1]).getBytes(StandardCharsets.US_ASCII));
        return verifier.verify(Base64.getUrlDecoder().decode(parts[2]));
    }

    @Test
    void createsStandardEdDsaCompactJwsAndPublishesMatchingKey() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("Ed25519");
        KeyPair pair = generator.generateKeyPair();
        PlatformProofSigningKey key = key(pair);
        PlatformCapabilityProofSigner signer = new PlatformCapabilityProofSigner(
                key, MAPPER, "test-platform", 300);

        var issued = signer.issue(Map.of("sub", "42", "modId", "com.example.test", "capability", "host.tasks.create"));
        String[] parts = issued.token().split("\\.");
        assertEquals(3, parts.length);
        var header = decodePart(issued.token(), 0);
        var payload = decodePart(issued.token(), 1);
        assertEquals("EdDSA", header.path("alg").asText());
        assertEquals("JWT", header.path("typ").asText());
        assertEquals(key.keyId(), header.path("kid").asText());
        assertEquals("test-platform", payload.path("iss").asText());
        assertEquals("42", payload.path("sub").asText());
        assertEquals("MOD_CAPABILITY_AUTHORIZATION", payload.path("proofType").asText());
        assertTrue(payload.path("exp").asLong() - payload.path("iat").asLong() <= 300);
        assertTrue(verifies(issued.token(), publicBase64(pair)));

        String tamperedPayload = parts[1].substring(0, parts[1].length() - 1)
                + (parts[1].endsWith("A") ? "B" : "A");
        Signature tamperVerifier = Signature.getInstance("Ed25519");
        tamperVerifier.initVerify(pair.getPublic());
        tamperVerifier.update((parts[0] + "." + tamperedPayload).getBytes(StandardCharsets.US_ASCII));
        assertFalse(tamperVerifier.verify(Base64.getUrlDecoder().decode(parts[2])));

        Map<String, Object> publicKey = signer.publicKey(key.keyId());
        assertEquals(key.keyId(), publicKey.get("keyId"));
        assertEquals("ACTIVE", publicKey.get("status"));
        assertEquals(true, publicKey.get("canVerify"));
        assertThrows(ResponseStatusException.class, () -> signer.publicKey("0".repeat(64)));
        assertEquals(key.keyId(), signer.publicKeys().get("activeKeyId"));
    }

    @Test
    void oldProofRemainsVerifiableAfterRotationAndNewProofUsesNewActiveKey() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("Ed25519");
        KeyPair oldPair = generator.generateKeyPair();
        KeyPair newPair = generator.generateKeyPair();

        PlatformCapabilityProofSigner oldSigner = new PlatformCapabilityProofSigner(
                key(oldPair), MAPPER, "test-platform", 300);
        String oldProof = oldSigner.issue(Map.of("sub", "42", "modId", "com.example.test")).token();

        String newKeyId = keyId(newPair);
        String oldKeyId = keyId(oldPair);
        String ringJson = keyRingJson(List.of(
                keyEntry(newPair, "ACTIVE", true),
                keyEntry(oldPair, "VERIFY_ONLY", false)));
        PlatformProofSigningKey rotatedRing = new PlatformProofSigningKey("", "", ringJson, newKeyId);
        PlatformCapabilityProofSigner rotatedSigner = new PlatformCapabilityProofSigner(
                rotatedRing, MAPPER, "test-platform", 300);

        String newProof = rotatedSigner.issue(Map.of("sub", "43", "modId", "com.example.test")).token();
        assertEquals(newKeyId, decodePart(newProof, 0).path("kid").asText());
        assertTrue(verifies(newProof, publicBase64(newPair)));

        Map<String, Object> oldMetadata = rotatedSigner.publicKey(oldKeyId);
        assertEquals("VERIFY_ONLY", oldMetadata.get("status"));
        assertEquals(true, oldMetadata.get("canVerify"));
        assertEquals(false, oldMetadata.get("canSign"));
        assertTrue(verifies(oldProof, (String) oldMetadata.get("publicKeyX509Base64")));

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> publishedKeys = (List<Map<String, Object>>) rotatedSigner.publicKeys().get("keys");
        assertEquals(2, publishedKeys.size());
        assertEquals(newKeyId, rotatedSigner.publicKeys().get("activeKeyId"));
    }

    @Test
    void emergencyRevocationRemovesKeyFromVerificationTrust() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("Ed25519");
        KeyPair activePair = generator.generateKeyPair();
        KeyPair compromisedPair = generator.generateKeyPair();
        String ringJson = keyRingJson(List.of(
                keyEntry(activePair, "ACTIVE", true),
                keyEntry(compromisedPair, "REVOKED", false)));
        PlatformProofSigningKey ring = new PlatformProofSigningKey("", "", ringJson, keyId(activePair));
        PlatformCapabilityProofSigner signer = new PlatformCapabilityProofSigner(
                ring, MAPPER, "test-platform", 300);

        ResponseStatusException error = assertThrows(ResponseStatusException.class,
                () -> signer.publicKey(keyId(compromisedPair)));
        assertEquals(HttpStatus.GONE, error.getStatusCode());

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> publishedKeys = (List<Map<String, Object>>) signer.publicKeys().get("keys");
        Map<String, Object> revoked = publishedKeys.stream()
                .filter(item -> item.get("keyId").equals(keyIdUnchecked(compromisedPair)))
                .findFirst().orElseThrow();
        assertEquals("REVOKED", revoked.get("status"));
        assertEquals(false, revoked.get("canVerify"));
        assertFalse(revoked.containsKey("publicKeyX509Base64"));
    }

    @Test
    void rejectsInvalidKeyRingStatesAndActiveKeySelection() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("Ed25519");
        KeyPair first = generator.generateKeyPair();
        KeyPair second = generator.generateKeyPair();

        assertThrows(IllegalStateException.class, () -> new PlatformProofSigningKey("", "",
                keyRingJson(List.of(keyEntry(first, "ACTIVE", true), keyEntry(second, "ACTIVE", true))), ""));
        assertThrows(IllegalStateException.class, () -> new PlatformProofSigningKey("", "",
                keyRingJson(List.of(keyEntry(first, "ACTIVE", true))), "0".repeat(64)));
        assertThrows(IllegalStateException.class, () -> new PlatformProofSigningKey("", "",
                keyRingJson(List.of(keyEntry(first, "VERIFY_ONLY", false))), ""));
        assertThrows(IllegalStateException.class, () -> new PlatformProofSigningKey("", "",
                keyRingJson(List.of(keyEntry(first, "VERIFY_ONLY", true), keyEntry(second, "ACTIVE", true))), ""));
    }

    @Test
    void missingSigningKeyFailsClosed() {
        PlatformProofSigningKey key = new PlatformProofSigningKey("", "");
        PlatformCapabilityProofSigner signer = new PlatformCapabilityProofSigner(
                key, MAPPER, "test-platform", 300);
        assertThrows(ResponseStatusException.class, () -> signer.issue(Map.of("sub", "42")));
        assertThrows(ResponseStatusException.class, () -> signer.publicKey("anything"));
    }

    @Test
    void rejectsMismatchedPrivateAndPublicKeys() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("Ed25519");
        KeyPair first = generator.generateKeyPair();
        KeyPair second = generator.generateKeyPair();
        assertThrows(IllegalStateException.class, () -> new PlatformProofSigningKey(
                privateBase64(first), publicBase64(second)));
    }
}
