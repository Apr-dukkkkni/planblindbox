package com.planblindbox.mod.sync;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

/** Authenticated, write-once metadata for client-side encryption. No key/phrase is accepted. */
@RestController
@RequestMapping("/api/v1/me/sync/crypto")
public class CoreSyncCryptoController {
    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper;
    private final SyncEntitlementService entitlement;

    public CoreSyncCryptoController(JdbcTemplate jdbc, ObjectMapper mapper,
            SyncEntitlementService entitlement) {
        this.jdbc = jdbc;
        this.mapper = mapper;
        this.entitlement = entitlement;
    }

    public record Setup(String salt, int iterations, JsonNode verifier) {}

    private long owner(Jwt jwt) {
        if (jwt == null) throw new ResponseStatusException(HttpStatus.UNAUTHORIZED);
        return Long.parseLong(jwt.getSubject());
    }

    @GetMapping
    public Map<String, Object> get(@AuthenticationPrincipal Jwt jwt) {
        var result = jdbc.query("SELECT salt_base64,iterations,verifier_json FROM user_sync_crypto_config WHERE user_id=?",
            (rs, i) -> Map.<String, Object>of(
                "configured", true,
                "salt", rs.getString(1),
                "iterations", rs.getInt(2),
                "verifier", parse(rs.getString(3))), owner(jwt));
        return result.isEmpty() ? Map.of("configured", false) : result.get(0);
    }

    @PutMapping
    public Map<String, Object> create(@AuthenticationPrincipal Jwt jwt, @RequestBody Setup request) {
        long uid = owner(jwt);
        entitlement.require(uid);
        if (request == null || request.iterations() != 210000 || request.salt() == null ||
            request.verifier() == null || !request.verifier().isObject() ||
            request.verifier().toString().length() > 2048 || !validB64(request.salt(),16,16) ||
            !"aes-256-gcm".equals(request.verifier().path("alg").asText()) ||
            request.verifier().path("keyVersion").asInt() != 1 ||
            !validB64(request.verifier().path("nonce").asText(),12,12) ||
            !validB64(request.verifier().path("tag").asText(),16,16) ||
            !validB64(request.verifier().path("ciphertext").asText(),1,1024)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "私密同步密钥参数无效");
        }
        try {
            jdbc.update("INSERT INTO user_sync_crypto_config(user_id,salt_base64,iterations,verifier_json) VALUES(?,?,?,?)",
                uid, request.salt(), request.iterations(), request.verifier().toString());
        } catch (DuplicateKeyException duplicate) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "私密同步已在其他设备初始化，不能覆盖恢复参数");
        }
        return get(jwt);
    }

    private JsonNode parse(String value) {
        try { return mapper.readTree(value); }
        catch (Exception e) { throw new IllegalStateException("私密同步参数已损坏",e); }
    }
    private boolean validB64(String encoded, int min, int max) {
        if (encoded == null || encoded.length() > 2048) return false;
        try {
            int length = Base64.getDecoder().decode(encoded).length;
            return length >= min && length <= max;
        } catch (IllegalArgumentException e) { return false; }
    }
}
