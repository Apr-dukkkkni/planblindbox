package com.planblindbox.mod;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.Signature;
import java.util.Base64;
import java.util.HexFormat;
import java.util.Map;
import java.security.MessageDigest;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest
@AutoConfigureMockMvc
class ModCapabilityAuthorizationIntegrationTest {
    private static final String MOD_ID = "com.example.approvaltest";
    private static final String VERSION = "1.0.0";
    private static final long USER_ID = 987654321L;
    private static final String CAPABILITY = "host.tasks.create";

    @Autowired MockMvc mvc;
    @Autowired JdbcTemplate jdbc;
    @Autowired ObjectMapper mapper;
    private KeyPair publisherKeyPair;
    private String publisherKeyId;

    private static final PlatformTestKey PLATFORM_TEST_KEY = createPlatformTestKey();

    private record PlatformTestKey(String keyRingJson) {}

    private static PlatformTestKey createPlatformTestKey() {
        try {
            KeyPairGenerator generator = KeyPairGenerator.getInstance("Ed25519");
            KeyPair pair = generator.generateKeyPair();
            String publicKey = Base64.getEncoder().encodeToString(pair.getPublic().getEncoded());
            String privateKey = Base64.getEncoder().encodeToString(pair.getPrivate().getEncoded());
            String keyId = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(pair.getPublic().getEncoded()));
            return new PlatformTestKey("[{\"keyId\":\"" + keyId
                    + "\",\"publicKeyX509Base64\":\"" + publicKey
                    + "\",\"privateKeyPkcs8Base64\":\"" + privateKey
                    + "\",\"status\":\"ACTIVE\"}]");
        } catch (Exception e) {
            throw new ExceptionInInitializerError(e);
        }
    }

    @DynamicPropertySource
    static void platformSigningProperties(DynamicPropertyRegistry registry) {
        registry.add("mod.platform-signing.private-key-pkcs8-base64", () -> "");
        registry.add("mod.platform-signing.public-key-x509-base64", () -> "");
        registry.add("mod.platform-signing.active-key-id", () -> "");
        registry.add("mod.platform-signing.key-ring-json", () -> PLATFORM_TEST_KEY.keyRingJson());
        registry.add("mod.platform-signing.issuer", () -> "planblindbox-mod-server");
        registry.add("mod.platform-signing.ttl-seconds", () -> "300");
    }

    private final String manifest = """
      {"manifestVersion":1,"id":"com.example.approvaltest","version":"1.0.0",
       "name":{"zh-CN":"审批测试 MOD"},"description":"backend capability approval integration test",
       "publisher":{"id":"publisher.example"},"type":"content","contentKind":"task_template",
       "runtime":{"type":"declarative","apiVersion":"1","entrypoint":"content/task-templates.json"},
       "compatibility":{"hostApi":"^1.0.0","platforms":["android"]},
       "ui":{"allowedModes":["modal"],"defaultMode":"modal"},
       "storage":{"local":{"enabled":false,"quotaMiB":0,"persistent":false}},
       "permissions":[{"capability":"host.tasks.create","required":true,"reason":"用户选择模板后创建任务"}],
       "dependencies":[],"assets":{}}
      """;

    @BeforeEach
    void clean() throws Exception {
        jdbc.update("DELETE FROM mod_capability_approval_audit WHERE mod_id=?", MOD_ID);
        jdbc.update("DELETE FROM mod_publisher_signing_key_audit WHERE publisher_id=?", "publisher.example");
        jdbc.update("DELETE FROM mod_publisher_signing_key WHERE publisher_id=?", "publisher.example");
        jdbc.update("DELETE FROM user_mod_capability_grant_audit WHERE mod_id=?", MOD_ID);
        jdbc.update("DELETE FROM user_mod_capability_grant WHERE mod_id=?", MOD_ID);
        jdbc.update("DELETE FROM mod_capability_approval WHERE mod_id=?", MOD_ID);
        jdbc.update(
                "DELETE FROM mod_download_outbox WHERE mod_id=?",
                MOD_ID
        );

        jdbc.update(
                "DELETE FROM mod_download_events WHERE mod_id=?",
                MOD_ID
        );
        jdbc.update("DELETE FROM mod_versions WHERE mod_id=?", MOD_ID);
        jdbc.update("DELETE FROM mod_packages WHERE mod_id=?", MOD_ID);
        jdbc.update("DELETE FROM community_user WHERE user_id=?", USER_ID);
        jdbc.update("INSERT INTO community_user(user_id,username,email,password_hash,gender,status,credential_version) VALUES (?,?,?,?,?,?,?)",
                USER_ID, "cap-test", "cap-test@example.invalid", null, "unspecified", "ACTIVE", 0L);
        KeyPairGenerator generator = KeyPairGenerator.getInstance("Ed25519");
        publisherKeyPair = generator.generateKeyPair();
        byte[] encoded = publisherKeyPair.getPublic().getEncoded();
        publisherKeyId = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(encoded));
        mvc.perform(post("/api/v1/admin/publishers/{publisher}/keys", "publisher.example")
                .header("Authorization", "Bearer test-only-token")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"publicKeyBase64\":\"" + Base64.getEncoder().encodeToString(encoded) + "\"}"))
                .andExpect(status().isOk());
    }

    @Test
    void v1PublishRequiresBothAdminApprovalAndUserGrantAndSupportsRevocation() throws Exception {
        mvc.perform(signedPublishRequest())
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(MOD_ID));

        mvc.perform(get("/api/v1/mods/{id}/versions/{version}/manifest", MOD_ID, VERSION))
                .andExpect(status().isOk())
                .andExpect(header().exists("X-Publisher-Key-Id"))
                .andExpect(header().exists("X-Publisher-Signature"));
        mvc.perform(get("/api/v1/publishers/{publisher}/keys/{keyId}", "publisher.example", publisherKeyId))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.algorithm").value("Ed25519"))
                .andExpect(jsonPath("$.status").value("ACTIVE"));
        mvc.perform(post("/api/v1/mods/{id}/versions/{version}/download", MOD_ID, VERSION)
                        .with(jwt().jwt(token -> token.subject(Long.toString(USER_ID))))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"requestId\":\"b6d1a2f0-91f0-4bd8-9f8c-3e3e4c2a8a11\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.publisherKeyId").value(publisherKeyId))
                .andExpect(jsonPath("$.publisherSignature").isNotEmpty());

        mvc.perform(get("/api/v1/me/mods/{id}/versions/{version}/capabilities/{cap}", MOD_ID, VERSION, CAPABILITY)
                        .with(jwt().jwt(token -> token.subject(Long.toString(USER_ID)))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.adminApproved").value(false))
                .andExpect(jsonPath("$.userGranted").value(false))
                .andExpect(jsonPath("$.effective").value(false));

        mvc.perform(put("/api/v1/admin/mods/{id}/versions/{version}/capabilities/{cap}/approval", MOD_ID, VERSION, CAPABILITY)
                        .header("Authorization", "Bearer test-only-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"approved\":true,\"reason\":\"通过安全审查\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.adminApproved").value(true))
                .andExpect(jsonPath("$.effective").value(false));

        mvc.perform(put("/api/v1/me/mods/{id}/versions/{version}/capabilities/{cap}", MOD_ID, VERSION, CAPABILITY)
                        .with(jwt().jwt(token -> token.subject(Long.toString(USER_ID))))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"granted\":true}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.adminApproved").value(true))
                .andExpect(jsonPath("$.userGranted").value(true))
                .andExpect(jsonPath("$.effective").value(true));

        mvc.perform(delete("/api/v1/me/mods/{id}/versions/{version}/capabilities/{cap}", MOD_ID, VERSION, CAPABILITY)
                        .with(jwt().jwt(token -> token.subject(Long.toString(USER_ID)))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.userGranted").value(false))
                .andExpect(jsonPath("$.effective").value(false));
    }

    @Test
    void issuedProofIsOnlineVerifiedAndInvalidatedByRevocationRegrantAndVisibilityChanges() throws Exception {
        mvc.perform(signedPublishRequest()).andExpect(status().isOk());
        mvc.perform(put("/api/v1/admin/mods/{id}/versions/{version}/capabilities/{cap}/approval", MOD_ID, VERSION, CAPABILITY)
                        .header("Authorization", "Bearer test-only-token")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"approved\":true}"))
                .andExpect(status().isOk());
        mvc.perform(put("/api/v1/me/mods/{id}/versions/{version}/capabilities/{cap}", MOD_ID, VERSION, CAPABILITY)
                        .with(jwt().jwt(token -> token.subject(Long.toString(USER_ID))))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"granted\":true}"))
                .andExpect(status().isOk());

        String proof = issueProof();
        verifyProof(proof, VERSION).andExpect(status().isOk())
                .andExpect(jsonPath("$.active").value(true))
                .andExpect(jsonPath("$.modId").value(MOD_ID));

        // A proof for one version/capability cannot be replayed for another resource context.
        verifyProof(proof, "2.0.0").andExpect(status().isForbidden());

        // Revoking and then re-granting must not resurrect an older still-unexpired proof.
        mvc.perform(delete("/api/v1/me/mods/{id}/versions/{version}/capabilities/{cap}", MOD_ID, VERSION, CAPABILITY)
                        .with(jwt().jwt(token -> token.subject(Long.toString(USER_ID)))))
                .andExpect(status().isOk());
        verifyProof(proof, VERSION).andExpect(status().isForbidden());
        mvc.perform(put("/api/v1/me/mods/{id}/versions/{version}/capabilities/{cap}", MOD_ID, VERSION, CAPABILITY)
                        .with(jwt().jwt(token -> token.subject(Long.toString(USER_ID))))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"granted\":true}"))
                .andExpect(status().isOk());
        verifyProof(proof, VERSION).andExpect(status().isForbidden());

        String afterRegrant = issueProof();
        verifyProof(afterRegrant, VERSION).andExpect(status().isOk()).andExpect(jsonPath("$.active").value(true));

        // Reject -> re-approve also invalidates previously issued proofs, even when the final gate is true.
        mvc.perform(put("/api/v1/admin/mods/{id}/versions/{version}/capabilities/{cap}/approval", MOD_ID, VERSION, CAPABILITY)
                        .header("Authorization", "Bearer test-only-token")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"approved\":false}"))
                .andExpect(status().isOk());
        verifyProof(afterRegrant, VERSION).andExpect(status().isForbidden());
        mvc.perform(put("/api/v1/admin/mods/{id}/versions/{version}/capabilities/{cap}/approval", MOD_ID, VERSION, CAPABILITY)
                        .header("Authorization", "Bearer test-only-token")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"approved\":true}"))
                .andExpect(status().isOk());
        verifyProof(afterRegrant, VERSION).andExpect(status().isForbidden());
        String afterReapproval = issueProof();
        verifyProof(afterReapproval, VERSION).andExpect(status().isOk()).andExpect(jsonPath("$.active").value(true));

        // Disable -> re-enable increments the package authorization revision, invalidating old proofs.
        mvc.perform(patch("/api/v1/admin/mods/{id}/visibility", MOD_ID)
                        .header("Authorization", "Bearer test-only-token")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"enabled\":false}"))
                .andExpect(status().isOk());
        mvc.perform(patch("/api/v1/admin/mods/{id}/visibility", MOD_ID)
                        .header("Authorization", "Bearer test-only-token")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"enabled\":true}"))
                .andExpect(status().isOk());
        verifyProof(afterReapproval, VERSION).andExpect(status().isForbidden());
    }

    @Test
    void publisherKeyRevocationInvalidatesAlreadyIssuedProof() throws Exception {
        mvc.perform(signedPublishRequest()).andExpect(status().isOk());
        mvc.perform(put("/api/v1/admin/mods/{id}/versions/{version}/capabilities/{cap}/approval", MOD_ID, VERSION, CAPABILITY)
                        .header("Authorization", "Bearer test-only-token")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"approved\":true}"))
                .andExpect(status().isOk());
        mvc.perform(put("/api/v1/me/mods/{id}/versions/{version}/capabilities/{cap}", MOD_ID, VERSION, CAPABILITY)
                        .with(jwt().jwt(token -> token.subject(Long.toString(USER_ID))))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"granted\":true}"))
                .andExpect(status().isOk());
        String proof = issueProof();

        mvc.perform(delete("/api/v1/admin/publishers/{publisher}/keys/{keyId}", "publisher.example", publisherKeyId)
                        .header("Authorization", "Bearer test-only-token"))
                .andExpect(status().isOk());
        verifyProof(proof, VERSION).andExpect(status().isUnauthorized());
    }

    private String issueProof() throws Exception {
        String body = mvc.perform(post("/api/v1/me/mods/{id}/versions/{version}/capabilities/{cap}/proof",
                        MOD_ID, VERSION, CAPABILITY)
                        .with(jwt().jwt(token -> token.subject(Long.toString(USER_ID)))))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        JsonNode response = mapper.readTree(body);
        return response.path("token").asText();
    }

    private org.springframework.test.web.servlet.ResultActions verifyProof(String proof, String expectedVersion)
            throws Exception {
        String body = mapper.writeValueAsString(Map.of(
                "token", proof, "modId", MOD_ID, "version", expectedVersion, "capability", CAPABILITY));
        return mvc.perform(post("/api/v1/me/mod-capability-proofs/verify")
                .with(jwt().jwt(token -> token.subject(Long.toString(USER_ID))))
                .contentType(MediaType.APPLICATION_JSON).content(body));
    }

    @Test
    void adminCannotApproveCapabilityNotDeclaredByManifest() throws Exception {
        mvc.perform(signedPublishRequest())
                .andExpect(status().isOk());
        mvc.perform(put("/api/v1/admin/mods/{id}/versions/{version}/capabilities/{cap}/approval", MOD_ID, VERSION, "host.habits.create")
                        .header("Authorization", "Bearer test-only-token")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"approved\":true}"))
                .andExpect(status().isForbidden());
    }

    @Test
    void legacyManifestPublishRemainsSupported() throws Exception {
        String legacy = """
          {"schemaVersion":1,"id":"com.example.legacyapproval","name":"Legacy","version":"1.0.0",
           "permissions":["tasks.create"],"dependencies":[],"taskTemplates":[]}
          """;
        mvc.perform(post("/api/v1/admin/mods/publish").header("Authorization", "Bearer test-only-token")
                        .contentType(MediaType.APPLICATION_JSON).content(legacy))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("PUBLISHED"));
    }

    private org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder signedPublishRequest() throws Exception {
        Signature signer = Signature.getInstance("Ed25519");
        signer.initSign(publisherKeyPair.getPrivate());
        signer.update(manifest.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        String signature = Base64.getEncoder().encodeToString(signer.sign());
        return post("/api/v1/admin/mods/publish")
                .header("Authorization", "Bearer test-only-token")
                .header("X-Publisher-Key-Id", publisherKeyId)
                .header("X-Publisher-Signature", signature)
                .contentType(MediaType.APPLICATION_JSON).content(manifest);
    }

    @Test
    void v1PublishRejectsUnsignedAndTamperedManifest() throws Exception {
        mvc.perform(post("/api/v1/admin/mods/publish").header("Authorization", "Bearer test-only-token")
                        .contentType(MediaType.APPLICATION_JSON).content(manifest))
                .andExpect(status().isUnauthorized());

        Signature signer = Signature.getInstance("Ed25519");
        signer.initSign(publisherKeyPair.getPrivate());
        signer.update(manifest.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        String signature = Base64.getEncoder().encodeToString(signer.sign());
        String tampered = manifest.replace("审批测试 MOD", "被篡改 MOD");
        mvc.perform(post("/api/v1/admin/mods/publish").header("Authorization", "Bearer test-only-token")
                        .header("X-Publisher-Key-Id", publisherKeyId)
                        .header("X-Publisher-Signature", signature)
                        .contentType(MediaType.APPLICATION_JSON).content(tampered))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void revokedPublisherKeyCannotPublish() throws Exception {
        mvc.perform(delete("/api/v1/admin/publishers/{publisher}/keys/{keyId}", "publisher.example", publisherKeyId)
                        .header("Authorization", "Bearer test-only-token"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("REVOKED"));
        mvc.perform(signedPublishRequest()).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/v1/publishers/{publisher}/keys/{keyId}", "publisher.example", publisherKeyId))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("REVOKED"));
    }

    @Test
    void publisherKeyMustBelongToManifestPublisher() throws Exception {
        String otherPublisherManifest = manifest.replace("publisher.example", "publisher.other");
        Signature signer = Signature.getInstance("Ed25519");
        signer.initSign(publisherKeyPair.getPrivate());
        signer.update(otherPublisherManifest.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        String signature = Base64.getEncoder().encodeToString(signer.sign());
        mvc.perform(post("/api/v1/admin/mods/publish").header("Authorization", "Bearer test-only-token")
                        .header("X-Publisher-Key-Id", publisherKeyId)
                        .header("X-Publisher-Signature", signature)
                        .contentType(MediaType.APPLICATION_JSON).content(otherPublisherManifest))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void publisherKeyEnrollmentRequiresAdminToken() throws Exception {
        mvc.perform(post("/api/v1/admin/publishers/{publisher}/keys", "publisher.other")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"publicKeyBase64\":\"" + Base64.getEncoder().encodeToString(publisherKeyPair.getPublic().getEncoded()) + "\"}"))
                .andExpect(status().isUnauthorized());
    }
}
