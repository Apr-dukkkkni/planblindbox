package com.planblindbox.mod.manifest;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.planblindbox.mod.domain.BadRequest;
import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class ManifestV1ValidatorTest {
    private final ManifestV1Validator validator = new ManifestV1Validator(new ObjectMapper());
    private final ObjectMapper mapper = new ObjectMapper();

    @Test
    void acceptsEverySharedValidVector() throws Exception {
        JsonNode vectors = mapper.readTree(Files.readString(findVectors()));
        for (JsonNode vector : vectors.path("valid")) {
            JsonNode manifest = validator.validate(vector.path("raw").asText());
            assertThat(manifest.path("manifestVersion").asInt())
                    .as(vector.path("id").asText())
                    .isEqualTo(1);
        }
    }

    @Test
    void rejectsEverySharedInvalidVector() throws Exception {
        JsonNode vectors = mapper.readTree(Files.readString(findVectors()));
        for (JsonNode vector : vectors.path("invalid")) {
            assertThatThrownBy(() -> validator.validate(vector.path("raw").asText()))
                    .as(vector.path("id").asText() + ": " + vector.path("reason").asText())
                    .isInstanceOf(BadRequest.class);
        }
    }

    @Test
    void semverUsesSemverTwoPrecedence() {
        assertThat(SemVerV1.compare("1.0.0-alpha.1", "1.0.0-alpha.beta")).isLessThan(0);
        assertThat(SemVerV1.compare("1.0.0-rc.1", "1.0.0")).isLessThan(0);
        assertThat(SemVerV1.compare("1.0.0+build.1", "1.0.0+build.2")).isZero();
        assertThat(SemVerV1.compare("1.10.0", "1.9.0")).isGreaterThan(0);
    }

    private Path findVectors() {
        Path current = Path.of("").toAbsolutePath();
        while (current != null) {
            Path candidate = current.resolve("mod-spec/conformance/manifest-v1-vectors.json");
            if (Files.isRegularFile(candidate)) return candidate;
            current = current.getParent();
        }
        throw new IllegalStateException("Cannot locate shared Manifest V1 conformance vectors");
    }
}
