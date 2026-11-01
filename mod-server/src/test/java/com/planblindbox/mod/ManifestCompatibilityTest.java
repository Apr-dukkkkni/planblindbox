package com.planblindbox.mod;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.planblindbox.mod.domain.BadRequest;
import com.planblindbox.mod.service.ManifestValidator;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class ManifestCompatibilityTest {
    private final ManifestValidator validator = new ManifestValidator(new ObjectMapper());
    private String raw(String field) {
        return "{\"schemaVersion\":1,\"id\":\"com.example.safe\",\"name\":\"示例\",\"version\":\"1.0.0\"" + field + "}";
    }
    @Test void acceptsOldAndNewManifests() {
        assertThat(validator.validate(raw("")).path("id").asText()).isEqualTo("com.example.safe");
        assertThat(validator.validate(raw(",\"minHostVersion\":\"0.1.0\"")).path("minHostVersion").asText())
            .isEqualTo("0.1.0");
    }
    @Test void rejectsInvalidCompatibilityVersionAndOversizedVersionParts() {
        assertThatThrownBy(() -> validator.validate(raw(",\"minHostVersion\":\"latest\"")))
            .isInstanceOf(BadRequest.class);
        assertThatThrownBy(() -> validator.validate("{\"schemaVersion\":1,\"id\":\"com.example.safe\",\"name\":\"示例\",\"version\":\"123456789012345678.0.0\"}"))
            .isInstanceOf(BadRequest.class);
    }
}
