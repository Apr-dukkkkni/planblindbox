package com.planblindbox.mod.sync;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

/** Core record protocol. No UI or SQLite implementation details are accepted here. */
@RestController
@RequestMapping("/api/v1/me/sync")
public class CoreSyncController {
    private static final Set<String> TYPES = Set.of(
        "task", "task_record", "habit", "habit_record", "category",
        "diary", "mood_custom"
    );
    private static final Set<String> PRIVATE_TYPES = Set.of("diary", "mood_custom");
    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper;
    private final SyncEntitlementService entitlement;

    public CoreSyncController(JdbcTemplate jdbc, ObjectMapper mapper, SyncEntitlementService entitlement) {
        this.jdbc = jdbc;
        this.mapper = mapper;
        this.entitlement = entitlement;
    }

    public record Mutation(String operationId, String type, String id,
                           long expectedRevision, boolean deleted, JsonNode payload) {}
    public record MutationResult(long revision, long cursor, boolean replayed) {}
    public record SyncRecord(String type, String id, long revision, boolean deleted,
                             JsonNode payload, long cursor, String changedAt) {}
    public record Page(long cursor, boolean hasMore, List<SyncRecord> changes) {}

    private long account(Jwt jwt) {
        if (jwt == null) throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "请先登录");
        return Long.parseLong(jwt.getSubject());
    }

    @GetMapping("/entitlement")
    public Map<String, Object> entitlement(@AuthenticationPrincipal Jwt jwt) {
        long userId = account(jwt);
        List<String> dates = jdbc.query(
            "SELECT expires_at FROM user_sync_entitlement WHERE user_id=?",
            (rs, index) -> rs.getTimestamp(1).toInstant().toString(), userId);
        return Map.of("active", entitlement.active(userId),
            "expiresAt", dates.isEmpty() ? "" : dates.get(0),
            "planCode", "core_sync_annual", "annualPriceCny", "9.90",
            "billingStatus", "payment_not_integrated",
            "canDownloadAfterExpiry", true);
    }

    @GetMapping("/changes")
    public Page changes(@AuthenticationPrincipal Jwt jwt,
                        @RequestParam(defaultValue = "0") long cursor,
                        @RequestParam(defaultValue = "100") int limit) {
        long userId = account(jwt);
        // Expired subscribers may still download their already stored data.
        if (cursor < 0 || limit < 1 || limit > 200) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "无效的同步游标或数量");
        }
        var result = jdbc.query(
            "SELECT sync_cursor,record_type,record_id,revision,deleted,payload,changed_at " +
            "FROM user_sync_change WHERE user_id=? AND sync_cursor>? ORDER BY sync_cursor ASC LIMIT ?",
            (rs, i) -> new SyncRecord(rs.getString("record_type"), rs.getString("record_id"),
                rs.getLong("revision"), rs.getBoolean("deleted"), parse(rs.getString("payload")),
                rs.getLong("sync_cursor"), rs.getTimestamp("changed_at").toInstant().toString()),
            userId, cursor, limit + 1);
        boolean more = result.size() > limit;
        List<SyncRecord> page = more ? result.subList(0, limit) : result;
        long next = page.isEmpty() ? cursor : page.get(page.size() - 1).cursor();
        return new Page(next, more, page);
    }

    @PutMapping("/records")
    @Transactional
    public MutationResult mutate(@AuthenticationPrincipal Jwt jwt, @RequestBody Mutation request) {
        long userId = account(jwt);
        entitlement.require(userId);
        validate(request);
        if (PRIVATE_TYPES.contains(request.type())) {
            Integer configured = jdbc.queryForObject(
                "SELECT COUNT(*) FROM user_sync_crypto_config WHERE user_id=?", Integer.class, userId);
            if (configured == null || configured == 0) {
                throw new ResponseStatusException(HttpStatus.PRECONDITION_REQUIRED,
                    "请先配置私密同步恢复口令");
            }
        }
        // Lock the account's stream before reading the record: guarantees cursor order
        // and prevents concurrent clients from both winning expectedRevision=0.
        jdbc.update("INSERT INTO user_sync_clock(user_id,sync_cursor) VALUES (?,0) " +
            "ON DUPLICATE KEY UPDATE sync_cursor=sync_cursor", userId);
        Long currentCursor = jdbc.queryForObject(
            "SELECT sync_cursor FROM user_sync_clock WHERE user_id=? FOR UPDATE", Long.class, userId);
        var replay = jdbc.query(
            "SELECT record_type,record_id,revision,sync_cursor,request_hash FROM user_sync_operation " +
            "WHERE user_id=? AND operation_id=?",
            (rs, i) -> Map.<String, Object>of("type",rs.getString(1),"id",rs.getString(2),
                "revision",rs.getLong(3),"cursor",rs.getLong(4),
                "hash",rs.getString(5)), userId, request.operationId());
        if (!replay.isEmpty()) {
            var old = replay.get(0);
            if (!old.get("type").equals(request.type()) || !old.get("id").equals(request.id()) ||
                !old.get("hash").equals(fingerprint(request))) {
                throw new ResponseStatusException(HttpStatus.CONFLICT, "operationId 不可用于其他记录");
            }
            return new MutationResult((long)old.get("revision"), (long)old.get("cursor"), true);
        }
        var revisions = jdbc.query(
            "SELECT revision FROM user_sync_record WHERE user_id=? AND record_type=? AND record_id=?",
            (rs, i) -> rs.getLong(1), userId, request.type(), request.id());
        long actual = revisions.isEmpty() ? 0 : revisions.get(0);
        if (actual != request.expectedRevision()) {
            // 409 never silently picks a winning client. Caller must fetch changes and resolve.
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "记录版本冲突，服务器当前版本 " + actual);
        }
        long revision = actual + 1;
        long next = currentCursor + 1;
        String body = request.deleted() ? null : request.payload().toString();
        if (actual == 0) {
            jdbc.update("INSERT INTO user_sync_record(user_id,record_type,record_id,revision,deleted,payload) " +
                "VALUES(?,?,?,?,?,?)", userId,request.type(),request.id(),revision,request.deleted(),body);
        } else {
            jdbc.update("UPDATE user_sync_record SET revision=?,deleted=?,payload=?,changed_at=CURRENT_TIMESTAMP " +
                "WHERE user_id=? AND record_type=? AND record_id=?",
                revision,request.deleted(),body,userId,request.type(),request.id());
        }
        jdbc.update("INSERT INTO user_sync_change(user_id,sync_cursor,record_type,record_id,revision,deleted,payload) " +
            "VALUES(?,?,?,?,?,?,?)",userId,next,request.type(),request.id(),revision,request.deleted(),body);
        jdbc.update("INSERT INTO user_sync_operation(user_id,operation_id,record_type,record_id,revision,sync_cursor,request_hash) " +
            "VALUES(?,?,?,?,?,?,?)",userId,request.operationId(),request.type(),request.id(),revision,next,fingerprint(request));
        jdbc.update("UPDATE user_sync_clock SET sync_cursor=? WHERE user_id=?",next,userId);
        return new MutationResult(revision,next,false);
    }

    private void validate(Mutation r) {
        if (r == null || r.operationId() == null || r.type() == null || r.id() == null ||
            r.expectedRevision() < 0 || !TYPES.contains(r.type()) ||
            r.id().length() > 80 || r.id().isBlank() ||
            r.operationId().length() > 64 || r.operationId().isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"同步记录标识无效");
        }
        try { UUID.fromString(r.operationId()); UUID.fromString(r.id()); }
        catch (IllegalArgumentException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"operationId 和 record id 必须为 UUID");
        }
        if (!r.deleted()) {
            if (r.payload() == null || !r.payload().isObject() ||
                r.payload().toString().getBytes(StandardCharsets.UTF_8).length > 65536) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"记录内容无效或超过64KiB");
            }
            if (PRIVATE_TYPES.contains(r.type()) &&
                (!"aes-256-gcm".equals(r.payload().path("alg").asText()) ||
                 r.payload().path("keyVersion").asInt() != 1 ||
                 !base64Size(r.payload().path("ciphertext").asText(), 1, 65536) ||
                 !base64Size(r.payload().path("nonce").asText(), 12, 12) ||
                 !base64Size(r.payload().path("tag").asText(), 16, 16))) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"敏感数据必须使用客户端加密信封");
            }
        }
    }

    private boolean base64Size(String encoded, int min, int max) {
        if (encoded == null || encoded.length() > 90000) return false;
        try {
            int bytes = java.util.Base64.getDecoder().decode(encoded).length;
            return bytes >= min && bytes <= max;
        } catch (IllegalArgumentException ex) { return false; }
    }

    private String fingerprint(Mutation m) {
        try {
            var digest = MessageDigest.getInstance("SHA-256");
            byte[] bytes = (m.type() + "\n" + m.id() + "\n" + m.expectedRevision() + "\n" +
                m.deleted() + "\n" + (m.payload() == null ? "" : m.payload().toString()))
                .getBytes(StandardCharsets.UTF_8);
            return HexFormat.of().formatHex(digest.digest(bytes));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    private JsonNode parse(String text) {
        if (text == null) return null;
        try { return mapper.readTree(text); }
        catch (Exception e) { throw new IllegalStateException("同步记录格式损坏",e); }
    }
}
