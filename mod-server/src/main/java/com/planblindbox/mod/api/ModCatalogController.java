package com.planblindbox.mod.api;

import com.fasterxml.jackson.databind.JsonNode;
import com.planblindbox.mod.service.ModCatalogService;
import com.planblindbox.mod.service.DownloadRateLimiter;
import com.planblindbox.mod.service.ManifestIntegrity;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.LinkedHashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/mods")
public class ModCatalogController {
    private final ModCatalogService service;
    private final DownloadRateLimiter limiter;
    public ModCatalogController(ModCatalogService service, DownloadRateLimiter limiter) {
        this.service=service; this.limiter=limiter;
    }
    @GetMapping
    public List<Map<String,Object>> list(@RequestParam(defaultValue="") String search,
         @RequestParam(defaultValue="0") int page,@RequestParam(defaultValue="20") int size) {
        return service.list(search,page,size);
    }
    @GetMapping("/{id:.+}")
    public Map<String,Object> detail(@PathVariable String id) {return service.detail(id);}
    @GetMapping(value="/{id:.+}/versions/{version}/manifest",produces=MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> manifest(@PathVariable String id,@PathVariable String version) {
        String manifest = service.manifest(id, version);
        return ResponseEntity.ok().contentType(MediaType.APPLICATION_JSON)
                .header("X-Mod-Manifest-SHA256", ManifestIntegrity.sha256(manifest))
                .body(manifest);
    }
    public record DownloadRequest(String requestId) {}
    @PostMapping("/{id:.+}/versions/{version}/download")
    public Map<String,Object> download(@PathVariable String id,@PathVariable String version,
                                       @RequestBody DownloadRequest request, HttpServletRequest httpRequest) {
        limiter.check(id, httpRequest.getRemoteAddr());
        Map<String,Object> result = service.download(id,version,request.requestId());
        // Keep the v2.4 transactional download and Outbox unchanged.
        Map<String,Object> response = new LinkedHashMap<>(result);
        response.put("manifestSha256", ManifestIntegrity.sha256((String) result.get("manifest")));
        return response;
    }
}
