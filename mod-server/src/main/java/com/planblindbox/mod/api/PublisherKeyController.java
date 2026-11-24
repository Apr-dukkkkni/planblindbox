package com.planblindbox.mod.api;

import com.planblindbox.mod.service.PublisherSigningKeyService;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/v1/publishers")
public class PublisherKeyController {
    private final PublisherSigningKeyService service;
    public PublisherKeyController(PublisherSigningKeyService service) { this.service = service; }

    @GetMapping("/{publisherId}/keys/{keyId}")
    public Map<String, Object> publicKey(@PathVariable String publisherId, @PathVariable String keyId) {
        return service.publicKey(publisherId, keyId);
    }
}
