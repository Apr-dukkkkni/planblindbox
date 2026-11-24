package com.planblindbox.mod.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.planblindbox.mod.domain.BadRequest;
import com.planblindbox.mod.manifest.ManifestV1Validator;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

@Service
public class ModCapabilityAuthorizationService {
    private static final Pattern MOD_ID = Pattern.compile("^[a-z][a-z0-9]*(\\.[a-z][a-z0-9-]*)+$");
    private static final Pattern CAPABILITY = Pattern.compile("^[a-z][a-z0-9]*(\\.[a-z][a-z0-9_]*)+$");
    private final JdbcTemplate jdbc;
    private final ManifestV1Validator validator;

    public ModCapabilityAuthorizationService(JdbcTemplate jdbc, ManifestV1Validator validator) {
        this.jdbc = jdbc; this.validator = validator;
    }

    private record Published(String raw, String hash, String publisherId, JsonNode manifest) {}

    private void checkIdentifiers(String modId, String capability) {
        if (modId == null || modId.length() > 100 || !MOD_ID.matcher(modId).matches()) throw new BadRequest("Mod ID 格式错误");
        if (capability == null || capability.length() > 80 || !CAPABILITY.matcher(capability).matches()) throw new BadRequest("capability 格式错误");
    }

    private Published published(String modId, String version, String capability) {
        checkIdentifiers(modId, capability);
        if (version == null || version.length() > 64 || !version.matches("[0-9A-Za-z.+-]{1,64}")) throw new BadRequest("版本号格式错误");
        List<String> rows = jdbc.query("SELECT manifest_json FROM mod_versions WHERE mod_id=? AND version=?",
                (rs, n) -> rs.getString(1), modId, version);
        if (rows.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "MOD 版本不存在");
        String raw = rows.get(0);
        JsonNode manifest = validator.validate(raw);
        if (!modId.equals(manifest.path("id").asText()) || !version.equals(manifest.path("version").asText()))
            throw new ResponseStatusException(HttpStatus.CONFLICT, "已发布 Manifest 身份与请求不一致");
        boolean declared = false;
        JsonNode permissions = manifest.path("permissions");
        if (permissions.isArray()) for (JsonNode permission : permissions) {
            if (capability.equals(permission.path("capability").asText())) { declared = true; break; }
        }
        if (!declared) throw new ResponseStatusException(HttpStatus.FORBIDDEN, "该版本未声明此 capability");
        return new Published(raw, ManifestIntegrity.sha256(raw), manifest.path("publisher").path("id").asText(), manifest);
    }

    @Transactional
    public Map<String, Object> decide(String modId, String version, String capability,
                                      boolean approved, String reason, String adminActor) {
        Published p = published(modId, version, capability);
        String safeReason = reason == null ? "" : reason.trim();
        if (safeReason.length() > 500) throw new BadRequest("审批理由不能超过 500 个字符");
        List<Integer> exists = jdbc.query("SELECT 1 FROM mod_capability_approval WHERE mod_id=? AND version=? AND manifest_sha256=? AND capability=? FOR UPDATE",
                (rs, n) -> rs.getInt(1), modId, version, p.hash, capability);
        if (exists.isEmpty()) {
            jdbc.update("INSERT INTO mod_capability_approval(mod_id,version,manifest_sha256,publisher_id,capability,approved,decision_reason,decided_by) VALUES (?,?,?,?,?,?,?,?)",
                    modId, version, p.hash, p.publisherId, capability, approved, safeReason, adminActor);
        } else {
            jdbc.update("UPDATE mod_capability_approval SET publisher_id=?,approved=?,decision_reason=?,decided_by=?,updated_at=CURRENT_TIMESTAMP WHERE mod_id=? AND version=? AND manifest_sha256=? AND capability=?",
                    p.publisherId, approved, safeReason, adminActor, modId, version, p.hash, capability);
        }
        jdbc.update("INSERT INTO mod_capability_approval_audit(mod_id,version,manifest_sha256,publisher_id,capability,approved,decision_reason,decided_by) VALUES (?,?,?,?,?,?,?,?)",
                modId, version, p.hash, p.publisherId, capability, approved, safeReason, adminActor);
        return statusFor(p, modId, version, capability, null);
    }

    @Transactional
    public Map<String, Object> setUserGrant(long userId, String modId, String version,
                                            String capability, boolean granted) {
        Published p = published(modId, version, capability);
        List<Integer> exists = jdbc.query("SELECT 1 FROM user_mod_capability_grant WHERE user_id=? AND mod_id=? AND version=? AND manifest_sha256=? AND capability=? FOR UPDATE",
                (rs, n) -> rs.getInt(1), userId, modId, version, p.hash, capability);
        jdbc.update("INSERT INTO user_mod_capability_grant_audit(user_id,mod_id,version,manifest_sha256,capability,granted) VALUES (?,?,?,?,?,?)",
                userId, modId, version, p.hash, capability, granted);
        if (exists.isEmpty()) {
            jdbc.update("INSERT INTO user_mod_capability_grant(user_id,mod_id,version,manifest_sha256,capability,granted,granted_at,revoked_at) VALUES (?,?,?,?,?,?,?,?)",
                    userId, modId, version, p.hash, capability, granted,
                    granted ? new java.sql.Timestamp(System.currentTimeMillis()) : null,
                    granted ? null : new java.sql.Timestamp(System.currentTimeMillis()));
        } else {
            jdbc.update("UPDATE user_mod_capability_grant SET granted=?,granted_at=?,revoked_at=?,updated_at=CURRENT_TIMESTAMP WHERE user_id=? AND mod_id=? AND version=? AND manifest_sha256=? AND capability=?",
                    granted, granted ? new java.sql.Timestamp(System.currentTimeMillis()) : null,
                    granted ? null : new java.sql.Timestamp(System.currentTimeMillis()),
                    userId, modId, version, p.hash, capability);
        }
        return statusFor(p, modId, version, capability, userId);
    }

    public Map<String, Object> userStatus(long userId, String modId, String version, String capability) {
        Published p = published(modId, version, capability);
        return statusFor(p, modId, version, capability, userId);
    }

    private Map<String, Object> statusFor(Published p, String modId, String version, String capability, Long userId) {
        Boolean approved = jdbc.query("SELECT approved FROM mod_capability_approval WHERE mod_id=? AND version=? AND manifest_sha256=? AND publisher_id=? AND capability=?",
                rs -> rs.next() ? rs.getBoolean(1) : null, modId, version, p.hash, p.publisherId, capability);
        Boolean granted = userId == null ? null : jdbc.query("SELECT granted FROM user_mod_capability_grant WHERE user_id=? AND mod_id=? AND version=? AND manifest_sha256=? AND capability=?",
                rs -> rs.next() ? rs.getBoolean(1) : null, userId, modId, version, p.hash, capability);
        boolean packageEnabled = Boolean.TRUE.equals(jdbc.query("SELECT enabled FROM mod_packages WHERE mod_id=?",
                rs -> rs.next() ? rs.getBoolean(1) : null, modId));
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("modId", modId); result.put("version", version); result.put("publisherId", p.publisherId);
        result.put("manifestSha256", p.hash); result.put("capability", capability);
        result.put("adminApproved", Boolean.TRUE.equals(approved));
        if (userId != null) result.put("userGranted", Boolean.TRUE.equals(granted));
        result.put("packageEnabled", packageEnabled);
        result.put("effective", userId != null && Boolean.TRUE.equals(approved) && Boolean.TRUE.equals(granted) && packageEnabled);
        return result;
    }
}
