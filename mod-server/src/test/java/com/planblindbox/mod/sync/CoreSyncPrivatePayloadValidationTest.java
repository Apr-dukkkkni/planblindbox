package com.planblindbox.mod.sync;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.util.Base64;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.server.ResponseStatusException;

/**
 * Contract tests for the server-side private-record envelope boundary.
 * The server checks envelope shape; AES-GCM authenticity is verified only by clients.
 */
class CoreSyncPrivatePayloadValidationTest {
    private static final String OPERATION_ID = "123e4567-e89b-42d3-a456-426614174010";
    private static final String RECORD_ID = "123e4567-e89b-42d3-a456-426614174011";

    private final ObjectMapper mapper = new ObjectMapper();
    private CoreSyncController controller;

    @BeforeEach
    void setUp() {
        controller = new CoreSyncController(null, mapper, null);
    }

    @Test
    void rejectsPlaintextForEveryPrivateRecordType() throws Exception {
        JsonNode plaintext = mapper.readTree("""
            {"business_date":"2026-11-06","diary":"private text","period":1}
            """);

        for (String type : new String[] {"private_blob", "diary", "mood_custom"}) {
            ResponseStatusException error = assertThrows(
                ResponseStatusException.class,
                () -> validate(mutation(type, plaintext, false))
            );
            assertEquals(HttpStatus.BAD_REQUEST, error.getStatusCode());
        }
    }

    @Test
    void acceptsExactV2AesGcmEnvelopeForPrivateBlob() {
        assertDoesNotThrow(() -> validate(mutation("private_blob", validEnvelope(), false)));
    }

    @Test
    void rejectsExtraFieldsAndUnsupportedKeyVersions() {
        ObjectNode extraField = validEnvelope();
        extraField.put("business_date", "2026-11-06");
        assertBadRequest(mutation("private_blob", extraField, false));

        ObjectNode wrongVersion = validEnvelope();
        wrongVersion.put("keyVersion", 1);
        assertBadRequest(mutation("private_blob", wrongVersion, false));
    }

    @Test
    void rejectsInvalidNonceTagAndCiphertextEncoding() {
        ObjectNode badNonce = validEnvelope();
        badNonce.put("nonce", Base64.getEncoder().encodeToString(new byte[11]));
        assertBadRequest(mutation("private_blob", badNonce, false));

        ObjectNode badTag = validEnvelope();
        badTag.put("tag", Base64.getEncoder().encodeToString(new byte[15]));
        assertBadRequest(mutation("private_blob", badTag, false));

        ObjectNode badCiphertext = validEnvelope();
        badCiphertext.put("ciphertext", "not-base64!");
        assertBadRequest(mutation("private_blob", badCiphertext, false));
    }

    @Test
    void ordinaryTaskPayloadRemainsAcceptedWithoutPrivateEnvelope() throws Exception {
        JsonNode taskPayload = mapper.readTree("""
            {"entity":{"title":"ordinary task title","note":"ordinary task note"},"records":[]}
            """);
        assertDoesNotThrow(() -> validate(mutation("task", taskPayload, false)));
    }

    @Test
    void deletedPrivateRecordDoesNotRequireAnEnvelope() {
        assertDoesNotThrow(() -> validate(mutation("private_blob", null, true)));
    }

    private ObjectNode validEnvelope() {
        ObjectNode envelope = mapper.createObjectNode();
        envelope.put("alg", "aes-256-gcm");
        envelope.put("keyVersion", 2);
        envelope.put("nonce", Base64.getEncoder().encodeToString(new byte[12]));
        envelope.put("ciphertext", Base64.getEncoder().encodeToString(new byte[32]));
        envelope.put("tag", Base64.getEncoder().encodeToString(new byte[16]));
        return envelope;
    }

    private CoreSyncController.Mutation mutation(String type, JsonNode payload, boolean deleted) {
        return new CoreSyncController.Mutation(
            OPERATION_ID, type, RECORD_ID, 0, deleted, payload
        );
    }

    private void validate(CoreSyncController.Mutation mutation) {
        ReflectionTestUtils.invokeMethod(controller, "validate", mutation);
    }

    private void assertBadRequest(CoreSyncController.Mutation mutation) {
        ResponseStatusException error = assertThrows(
            ResponseStatusException.class,
            () -> validate(mutation)
        );
        assertEquals(HttpStatus.BAD_REQUEST, error.getStatusCode());
    }
}
