package com.planblindbox.mod;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.planblindbox.mod.domain.BadRequest;
import com.planblindbox.mod.service.ManifestIntegrity;
import com.planblindbox.mod.service.ManifestValidator;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class ManifestIntegrityTest {
    private final ManifestValidator validator = new ManifestValidator(new ObjectMapper());

    @Test void sha256HashesExactUtf8Bytes() {
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                ManifestIntegrity.sha256("abc"));
        assertNotEquals(ManifestIntegrity.sha256("阅读"), ManifestIntegrity.sha256("阅览"));
    }

    @Test void rejectDuplicateTopLevelAndNestedKeys() {
        String raw = """
                {"schemaVersion":1,"id":"com.example.reading","name":"阅读","version":"1.0.0","permissions":[]}
                """;
        assertEquals("com.example.reading", validator.validate(raw).get("id").asText());
        assertThrows(BadRequest.class, () -> validator.validate(raw.replace("\"schemaVersion\":1,",
                "\"schemaVersion\":1,\"schemaVersion\":1,")));
        assertThrows(BadRequest.class, () -> validator.validate(raw.replace("\"permissions\":[]",
                "\"permissions\":[{\"key\":1,\"key\":2}]")));
    }
}
