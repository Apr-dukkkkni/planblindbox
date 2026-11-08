package com.planblindbox.mod.auth;

import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.server.ResponseStatusException;

/** Internal bridge to the pinned @serenity-kit/opaque RFC 9807 service. */
@Service
public class OpaqueProtocolClient {
    private final RestClient client;

    public OpaqueProtocolClient(RestClient.Builder builder,
            @Value("${opaque.service.url:http://127.0.0.1:8092}") String baseUrl,
            @Value("${opaque.service.internal-secret:}") String secret) {
        this.client = builder.baseUrl(baseUrl)
            .defaultHeader("X-PBB-Internal-Secret", secret)
            .build();
    }

    @SuppressWarnings("unchecked")
    public Map<String, Object> registrationStart(String identifier, String request) {
        return post("/internal/registration/start", Map.of(
            "userIdentifier", identifier, "registrationRequest", request));
    }

    @SuppressWarnings("unchecked")
    public Map<String, Object> loginStart(String identifier, String record, String request) {
        return post("/internal/login/start", Map.of(
            "userIdentifier", identifier,
            "registrationRecord", record,
            "startLoginRequest", request));
    }

    public void loginFinish(String challengeId, String request) {
        Map<String, Object> result = post("/internal/login/finish", Map.of(
            "challengeId", challengeId, "finishLoginRequest", request));
        if (!Boolean.TRUE.equals(result.get("authenticated"))) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "邮箱或密码错误");
        }
    }

    public String decoyRegistrationRecord() {
        Map<String, Object> result = get("/internal/decoy-record");
        Object value = result.get("registrationRecord");
        if (!(value instanceof String record) || record.isBlank()) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "OPAQUE 认证服务尚未准备完成");
        }
        return record;
    }

    @SuppressWarnings("unchecked")
    public String serverPublicKey() {
        Map<String, Object> result = get("/internal/public-key");
        Object value = result.get("serverStaticPublicKey");
        if (!(value instanceof String key) || key.isBlank()) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "OPAQUE 服务端公钥尚未配置");
        }
        return key;
    }

    private Map<String, Object> post(String path, Object body) {
        try {
            Map<?, ?> response = client.post().uri(path).body(body).retrieve().body(Map.class);
            if (response == null) throw new IllegalStateException("Empty OPAQUE service response");
            return (Map<String, Object>) response;
        } catch (org.springframework.web.client.RestClientResponseException error) {
            if (error.getStatusCode().value() == 401 ||
                (path.contains("/login/") && error.getStatusCode().value() == 400)) {
                throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "邮箱或密码错误");
            }
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "OPAQUE 认证服务暂不可用", error);
        } catch (RestClientException error) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "OPAQUE 认证服务暂不可用", error);
        }
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> get(String path) {
        try {
            Map<?, ?> response = client.get().uri(path).retrieve().body(Map.class);
            if (response == null) throw new IllegalStateException("Empty OPAQUE service response");
            return (Map<String, Object>) response;
        } catch (RestClientException error) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "OPAQUE 认证服务暂不可用", error);
        }
    }
}
