package com.planblindbox.mod.proof;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.planblindbox.mod.service.ModCapabilityAuthorizationService;
import com.planblindbox.mod.service.PublisherSigningKeyService;
import com.planblindbox.mod.service.ManifestIntegrity;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.server.ResponseStatusException;

import java.security.KeyPairGenerator;
import java.util.Base64;
import com.fasterxml.jackson.databind.JsonNode;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ModCapabilityProofServiceTest {
    private static final long USER_ID = 123L;
    private static final String MOD_ID = "com.example.test";
    private static final String VERSION = "1.2.3";
    private static final String CAPABILITY = "host.tasks.create";
    private static final String RAW = "{\"id\":\"com.example.test\",\"version\":\"1.2.3\",\"publisher\":{\"id\":\"publisher.example\"}}";

    @Mock ModCapabilityAuthorizationService authorization;
    @Mock PublisherSigningKeyService publisherKeys;
    @Mock JdbcTemplate jdbc;
    private ModCapabilityProofService service;

    @BeforeEach
    void setUp() throws Exception {
        var pair = KeyPairGenerator.getInstance("Ed25519").generateKeyPair();
        var key = new PlatformProofSigningKey(
                Base64.getEncoder().encodeToString(pair.getPrivate().getEncoded()),
                Base64.getEncoder().encodeToString(pair.getPublic().getEncoded()));
        var signer = new PlatformCapabilityProofSigner(key, new ObjectMapper(), "test-platform", 300);
        service = new ModCapabilityProofService(authorization, publisherKeys, signer, jdbc, new ObjectMapper());
    }

    @Test
    void issuesProofOnlyAfterEffectiveAuthorizationAndActivePublisherSignatureRecheck() throws Exception {
        when(authorization.userStatus(USER_ID, MOD_ID, VERSION, CAPABILITY)).thenReturn(effectiveStatus());
        when(jdbc.queryForMap(anyString(), eq(MOD_ID), eq(VERSION))).thenReturn(Map.of(
                "manifest_json", RAW, "publisher_key_id", "b".repeat(64), "publisher_signature", "signature"));

        Map<String, Object> response = service.issue(USER_ID, MOD_ID, VERSION, CAPABILITY);
        assertEquals("MOD_CAPABILITY_AUTHORIZATION", response.get("proofType"));
        assertEquals("EdDSA", response.get("algorithm"));
        assertNotNull(response.get("token"));
        JsonNode claims = decodePayload((String) response.get("token"));
        assertEquals(1, claims.path("proofVersion").asInt());
        assertEquals(Long.toString(USER_ID), claims.path("sub").asText());
        assertEquals(MOD_ID, claims.path("modId").asText());
        assertEquals(VERSION, claims.path("version").asText());
        assertEquals(ManifestIntegrity.sha256(RAW), claims.path("manifestSha256").asText());
        assertEquals("publisher.example", claims.path("publisherId").asText());
        assertEquals("b".repeat(64), claims.path("publisherKeyId").asText());
        assertEquals(CAPABILITY, claims.path("capability").asText());
        assertTrue(claims.path("adminApproved").asBoolean());
        assertTrue(claims.path("userGranted").asBoolean());
        assertTrue(claims.path("packageEnabled").asBoolean());
        verify(publisherKeys).verifyManifest("publisher.example", "b".repeat(64), "signature", RAW);
    }

    @Test
    void refusesProofWhenAnyAuthorizationGateIsFalse() {
        when(authorization.userStatus(USER_ID, MOD_ID, VERSION, CAPABILITY)).thenReturn(Map.of("effective", false));
        ResponseStatusException error = assertThrows(ResponseStatusException.class,
                () -> service.issue(USER_ID, MOD_ID, VERSION, CAPABILITY));
        assertEquals(HttpStatus.FORBIDDEN, error.getStatusCode());
        verifyNoInteractions(jdbc, publisherKeys);
    }

    @Test
    void refusesProofWhenPublisherKeyHasBeenRevoked() {
        when(authorization.userStatus(USER_ID, MOD_ID, VERSION, CAPABILITY)).thenReturn(effectiveStatus());
        when(jdbc.queryForMap(anyString(), eq(MOD_ID), eq(VERSION))).thenReturn(Map.of(
                "manifest_json", RAW, "publisher_key_id", "b".repeat(64), "publisher_signature", "signature"));
        doThrow(new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Publisher key revoked"))
                .when(publisherKeys).verifyManifest("publisher.example", "b".repeat(64), "signature", RAW);
        ResponseStatusException error = assertThrows(ResponseStatusException.class,
                () -> service.issue(USER_ID, MOD_ID, VERSION, CAPABILITY));
        assertEquals(HttpStatus.UNAUTHORIZED, error.getStatusCode());
    }

    @Test
    void refusesProofWhenManifestDigestDoesNotMatchAuthorizationSnapshot() {
        Map<String, Object> stale = new java.util.LinkedHashMap<>(effectiveStatus());
        stale.put("manifestSha256", "a".repeat(64));
        when(authorization.userStatus(USER_ID, MOD_ID, VERSION, CAPABILITY)).thenReturn(stale);
        when(jdbc.queryForMap(anyString(), eq(MOD_ID), eq(VERSION))).thenReturn(Map.of(
                "manifest_json", RAW, "publisher_key_id", "b".repeat(64), "publisher_signature", "signature"));

        ResponseStatusException error = assertThrows(ResponseStatusException.class,
                () -> service.issue(USER_ID, MOD_ID, VERSION, CAPABILITY));
        assertEquals(HttpStatus.CONFLICT, error.getStatusCode());
        verifyNoInteractions(publisherKeys);
    }

    @Test
    void refusesProofWhenIndividualAuthorizationGateIsNotTrue() {
        Map<String, Object> inconsistent = new java.util.LinkedHashMap<>(effectiveStatus());
        inconsistent.put("userGranted", false);
        when(authorization.userStatus(USER_ID, MOD_ID, VERSION, CAPABILITY)).thenReturn(inconsistent);

        ResponseStatusException error = assertThrows(ResponseStatusException.class,
                () -> service.issue(USER_ID, MOD_ID, VERSION, CAPABILITY));
        assertEquals(HttpStatus.FORBIDDEN, error.getStatusCode());
        verifyNoInteractions(jdbc, publisherKeys);
    }

    @Test
    void refusesProofWhenManifestIdentityDoesNotMatchRequestedRelease() {
        when(authorization.userStatus(USER_ID, MOD_ID, VERSION, CAPABILITY)).thenReturn(effectiveStatus());
        String wrongRelease = "{\"id\":\"com.example.other\",\"version\":\"1.2.3\",\"publisher\":{\"id\":\"publisher.example\"}}";
        Map<String, Object> matchingDigestButWrongIdentity = new java.util.LinkedHashMap<>(effectiveStatus());
        matchingDigestButWrongIdentity.put("manifestSha256", ManifestIntegrity.sha256(wrongRelease));
        when(authorization.userStatus(USER_ID, MOD_ID, VERSION, CAPABILITY)).thenReturn(matchingDigestButWrongIdentity);
        when(jdbc.queryForMap(anyString(), eq(MOD_ID), eq(VERSION))).thenReturn(Map.of(
                "manifest_json", wrongRelease, "publisher_key_id", "b".repeat(64), "publisher_signature", "signature"));

        ResponseStatusException error = assertThrows(ResponseStatusException.class,
                () -> service.issue(USER_ID, MOD_ID, VERSION, CAPABILITY));
        assertEquals(HttpStatus.CONFLICT, error.getStatusCode());
        verifyNoInteractions(publisherKeys);
    }

    private static Map<String, Object> effectiveStatus() {
        return Map.of(
                "modId", MOD_ID,
                "version", VERSION,
                "publisherId", "publisher.example",
                "manifestSha256", ManifestIntegrity.sha256(RAW),
                "capability", CAPABILITY,
                "adminApproved", true,
                "userGranted", true,
                "packageEnabled", true,
                "effective", true);
    }

    private static JsonNode decodePayload(String token) throws Exception {
        String[] parts = token.split("\\.");
        return new ObjectMapper().readTree(Base64.getUrlDecoder().decode(parts[1]));
    }
}
