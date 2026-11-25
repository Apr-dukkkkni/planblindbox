package com.planblindbox.mod.api;

import com.planblindbox.mod.service.ModCatalogService;
import com.planblindbox.mod.service.ModCapabilityAuthorizationService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.nio.charset.StandardCharsets;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.security.MessageDigest;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/admin/mods")
public class ModAdminController {
    private final ModCatalogService service;
    private final String token;
    private final ModCapabilityAuthorizationService capabilityService;
    public ModAdminController(ModCatalogService service, ModCapabilityAuthorizationService capabilityService,
            @Value("${mod.admin-token:}") String token) {
        this.service=service; this.capabilityService=capabilityService; this.token=token;
    }
    private void authorize(String header) {
        if(token == null || token.isBlank()) throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,"服务器尚未配置管理员令牌");
        String provided=header!=null && header.startsWith("Bearer ") ? header.substring(7) : "";
        if(!MessageDigest.isEqual(provided.getBytes(StandardCharsets.UTF_8),token.getBytes(StandardCharsets.UTF_8)))
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED,"管理员令牌错误");
    }
    @PostMapping(value="/publish",consumes=MediaType.APPLICATION_JSON_VALUE, produces=MediaType.APPLICATION_JSON_VALUE)
    public Map<String,String> publish(@RequestHeader(value="Authorization",required=false) String auth,
            @RequestHeader(value="X-Publisher-Key-Id",required=false) String publisherKeyId,
            @RequestHeader(value="X-Publisher-Signature",required=false) String publisherSignature,
            @RequestBody byte[] rawBytes) {
        authorize(auth);
        final String raw;
        try {
            raw = StandardCharsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(rawBytes)).toString();
        } catch (CharacterCodingException e) {
            throw new com.planblindbox.mod.domain.BadRequest("Manifest 必须使用合法 UTF-8 编码");
        }
        return service.publish(raw, publisherKeyId, publisherSignature);
    }
    public record VisibilityRequest(boolean enabled) {}
    public record CapabilityApprovalRequest(Boolean approved, String reason) {}

    @PutMapping("/{id:.+}/versions/{version}/capabilities/{capability}/approval")
    public Map<String,Object> capabilityApproval(
            @RequestHeader(value="Authorization",required=false) String auth,
            @PathVariable String id, @PathVariable String version, @PathVariable String capability,
            @RequestBody CapabilityApprovalRequest request) {
        authorize(auth);
        if (request == null || request.approved() == null) throw new com.planblindbox.mod.domain.BadRequest("approved 必须明确提供");
        return capabilityService.decide(id, version, capability, request.approved(), request.reason(), "configured-admin-token");
    }
    @PatchMapping("/{id:.+}/visibility")
    public Map<String,Object> visibility(@RequestHeader(value="Authorization",required=false) String auth,
         @PathVariable String id,@RequestBody VisibilityRequest request) {
        authorize(auth);return service.changeVisibility(id,request.enabled());
    }
}
