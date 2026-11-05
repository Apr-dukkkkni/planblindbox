package com.planblindbox.mod.api;

import com.planblindbox.mod.service.ModCatalogService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/admin/mods")
public class ModAdminController {
    private final ModCatalogService service;
    private final String token;
    public ModAdminController(ModCatalogService service,@Value("${mod.admin-token:}") String token) {
        this.service=service; this.token=token;
    }
    private void authorize(String header) {
        if(token == null || token.isBlank()) throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,"服务器尚未配置管理员令牌");
        String provided=header!=null && header.startsWith("Bearer ") ? header.substring(7) : "";
        if(!MessageDigest.isEqual(provided.getBytes(StandardCharsets.UTF_8),token.getBytes(StandardCharsets.UTF_8)))
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED,"管理员令牌错误");
    }
    @PostMapping(value="/publish",consumes=MediaType.APPLICATION_JSON_VALUE, produces=MediaType.APPLICATION_JSON_VALUE)
    public Map<String,String> publish(@RequestHeader(value="Authorization",required=false) String auth,@RequestBody String raw) {
        authorize(auth);return service.publish(raw);
    }
    public record VisibilityRequest(boolean enabled) {}
    @PatchMapping("/{id:.+}/visibility")
    public Map<String,Object> visibility(@RequestHeader(value="Authorization",required=false) String auth,
         @PathVariable String id,@RequestBody VisibilityRequest request) {
        authorize(auth);return service.changeVisibility(id,request.enabled());
    }
}
