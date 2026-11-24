package com.planblindbox.mod.api;

import com.planblindbox.mod.service.PublisherSigningKeyService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Map;

/** Admin-controlled publisher key enrollment. Enrollment must follow out-of-band identity checks. */
@RestController
@RequestMapping("/api/v1/admin/publishers")
public class PublisherKeyAdminController {
    private final PublisherSigningKeyService service;
    private final String token;

    public PublisherKeyAdminController(PublisherSigningKeyService service,
            @Value("${mod.admin-token:}") String token) {
        this.service = service;
        this.token = token;
    }

    private void authorize(String header) {
        if (token == null || token.isBlank()) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "服务器尚未配置管理员令牌");
        }
        String provided = header != null && header.startsWith("Bearer ") ? header.substring(7) : "";
        if (!MessageDigest.isEqual(provided.getBytes(StandardCharsets.UTF_8), token.getBytes(StandardCharsets.UTF_8))) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "管理员令牌错误");
        }
    }

    public record EnrollKeyRequest(String publicKeyBase64) {}

    @PostMapping("/{publisherId}/keys")
    public Map<String, Object> enroll(
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @PathVariable String publisherId,
            @RequestBody EnrollKeyRequest request) {
        authorize(authorization);
        if (request == null) throw new com.planblindbox.mod.domain.BadRequest("请求体不能为空");
        return service.enroll(publisherId, request.publicKeyBase64(), "configured-admin-token");
    }

    @DeleteMapping("/{publisherId}/keys/{keyId}")
    public Map<String, Object> revoke(
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @PathVariable String publisherId,
            @PathVariable String keyId) {
        authorize(authorization);
        return service.revoke(publisherId, keyId, "configured-admin-token");
    }
}
