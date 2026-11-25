package com.planblindbox.mod.proof;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.planblindbox.mod.service.ModCapabilityAuthorizationService;
import com.planblindbox.mod.service.PublisherSigningKeyService;
import com.planblindbox.mod.service.ManifestIntegrity;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.web.server.ResponseStatusException;

import java.util.LinkedHashMap;
import java.util.Map;

@Service
public class ModCapabilityProofService {
    private final ModCapabilityAuthorizationService authorization;
    private final PublisherSigningKeyService publisherKeys;
    private final PlatformCapabilityProofSigner signer;
    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper;

    public ModCapabilityProofService(ModCapabilityAuthorizationService authorization,
            PublisherSigningKeyService publisherKeys, PlatformCapabilityProofSigner signer,
            JdbcTemplate jdbc, ObjectMapper mapper) {
        this.authorization = authorization;
        this.publisherKeys = publisherKeys;
        this.signer = signer;
        this.jdbc = jdbc;
        this.mapper = mapper;
    }

    @Transactional(readOnly = true)
    public Map<String, Object> issue(long userId, String modId, String version, String capability) {
        if (userId <= 0) throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "用户身份无效");
        Map<String, Object> status = authorization.userStatus(userId, modId, version, capability);
        // Do not infer the individual gates from `effective` or hard-code them into the JWS.
        // Require every gate explicitly so a future status implementation cannot accidentally
        // mint a proof from a partially populated or inconsistent status response.
        if (!Boolean.TRUE.equals(status.get("effective"))
                || !Boolean.TRUE.equals(status.get("adminApproved"))
                || !Boolean.TRUE.equals(status.get("userGranted"))
                || !Boolean.TRUE.equals(status.get("packageEnabled"))) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "管理员审批、用户授权和 MOD 上架状态必须同时有效");
        }
        if (!modId.equals(status.get("modId"))
                || !version.equals(status.get("version"))
                || !capability.equals(status.get("capability"))) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "授权状态与请求的 MOD 版本或 capability 不一致");
        }

        Map<String, Object> versionRow;
        try {
            versionRow = jdbc.queryForMap("""
                    SELECT manifest_json,publisher_key_id,publisher_signature
                    FROM mod_versions WHERE mod_id=? AND version=?
                    """, modId, version);
        } catch (org.springframework.dao.EmptyResultDataAccessException e) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "MOD 版本不存在");
        }
        Object rawValue = versionRow.get("manifest_json");
        Object keyIdValue = versionRow.get("publisher_key_id");
        Object signatureValue = versionRow.get("publisher_signature");
        if (rawValue == null || keyIdValue == null || signatureValue == null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "MOD 版本缺少有效的 Publisher 签名信息");
        }
        String rawManifest = rawValue.toString();
        String publisherKeyId = keyIdValue.toString();
        String publisherSignature = signatureValue.toString();
        try {
            JsonNode manifest = mapper.readTree(rawManifest);
            String publisherId = manifest.path("publisher").path("id").asText("");
            String actualManifestSha256 = ManifestIntegrity.sha256(rawManifest);
            // Bind the proof to the exact bytes that were signed and stored for this release.
            // The authorization lookup and this row read must describe the same release.
            if (!actualManifestSha256.equals(status.get("manifestSha256"))) {
                throw new ResponseStatusException(HttpStatus.CONFLICT,
                        "授权状态中的 Manifest 摘要与已发布内容不一致");
            }
            if (!modId.equals(manifest.path("id").asText())
                    || !version.equals(manifest.path("version").asText())
                    || publisherId.isBlank()
                    || !publisherId.equals(status.get("publisherId"))) {
                throw new ResponseStatusException(HttpStatus.CONFLICT,
                        "已发布 Manifest 身份与授权状态不一致");
            }
            // Re-check the Publisher signature against the currently active key. A revoked key
            // therefore prevents new platform proofs from being issued.
            publisherKeys.verifyManifest(publisherId, publisherKeyId, publisherSignature, rawManifest);
            Map<String, Object> claims = new LinkedHashMap<>();
            claims.put("proofVersion", 1);
            claims.put("sub", Long.toString(userId));
            claims.put("modId", modId);
            claims.put("version", version);
            claims.put("manifestSha256", actualManifestSha256);
            claims.put("publisherId", publisherId);
            claims.put("publisherKeyId", publisherKeyId);
            claims.put("capability", capability);
            claims.put("adminApproved", status.get("adminApproved"));
            claims.put("userGranted", status.get("userGranted"));
            claims.put("packageEnabled", status.get("packageEnabled"));
            claims.put("approvalRevision", requiredRevision(status, "approvalRevision"));
            claims.put("grantRevision", requiredRevision(status, "grantRevision"));
            claims.put("packageRevision", requiredRevision(status, "packageRevision"));
            PlatformCapabilityProofSigner.IssuedProof proof = signer.issue(claims);
            Map<String, Object> response = new LinkedHashMap<>();
            response.put("proofType", "MOD_CAPABILITY_AUTHORIZATION");
            response.put("algorithm", "EdDSA");
            response.put("keyId", proof.keyId());
            response.put("token", proof.token());
            response.put("issuedAt", proof.issuedAt());
            response.put("expiresAt", proof.expiresAt());
            return response;
        } catch (ResponseStatusException e) {
            throw e;
        } catch (Exception e) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "MOD Manifest 无法用于签发授权证明");
        }
    }

    /**
     * Performs online introspection against current database state. Callers must supply the
     * exact resource context they intend to use; a valid proof for another version/capability
     * is not interchangeable.
     */
    @Transactional(readOnly = true, isolation = Isolation.READ_COMMITTED)
    public Map<String, Object> verify(long userId, String token,
            String expectedModId, String expectedVersion, String expectedCapability) {
        if (userId <= 0) throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "用户身份无效");
        Map<String, Object> claims = signer.verify(token);
        String subject = requiredText(claims, "sub");
        if (!Long.toString(userId).equals(subject)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "授权证明不属于当前用户");
        }
        if (!"1".equals(String.valueOf(claims.get("proofVersion")))) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "授权证明版本不受支持");
        }
        if (!Boolean.TRUE.equals(claims.get("adminApproved"))
                || !Boolean.TRUE.equals(claims.get("userGranted"))
                || !Boolean.TRUE.equals(claims.get("packageEnabled"))) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "授权证明中的授权门禁声明无效");
        }

        String modId = requiredText(claims, "modId");
        String version = requiredText(claims, "version");
        String capability = requiredText(claims, "capability");
        if (!modId.equals(expectedModId) || !version.equals(expectedVersion)
                || !capability.equals(expectedCapability)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "授权证明与当前请求的 MOD、版本或 capability 不匹配");
        }

        Map<String, Object> status = authorization.userStatus(userId, modId, version, capability);
        if (!Boolean.TRUE.equals(status.get("effective"))
                || !Boolean.TRUE.equals(status.get("adminApproved"))
                || !Boolean.TRUE.equals(status.get("userGranted"))
                || !Boolean.TRUE.equals(status.get("packageEnabled"))) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "授权证明已失效：当前授权门禁不再全部有效");
        }
        if (!modId.equals(status.get("modId")) || !version.equals(status.get("version"))
                || !capability.equals(status.get("capability"))
                || !requiredText(claims, "manifestSha256").equals(status.get("manifestSha256"))
                || !requiredText(claims, "publisherId").equals(status.get("publisherId"))) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "授权证明绑定的 Manifest 或 Publisher 已变化");
        }
        if (requiredRevision(claims, "approvalRevision") != requiredRevision(status, "approvalRevision")
                || requiredRevision(claims, "grantRevision") != requiredRevision(status, "grantRevision")
                || requiredRevision(claims, "packageRevision") != requiredRevision(status, "packageRevision")) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "授权证明已失效：管理员审批、用户授权或 MOD 状态发生过变化");
        }

        Map<String, Object> versionRow;
        try {
            versionRow = jdbc.queryForMap("""
                    SELECT manifest_json,publisher_key_id,publisher_signature
                    FROM mod_versions WHERE mod_id=? AND version=?
                    """, modId, version);
        } catch (org.springframework.dao.EmptyResultDataAccessException e) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "授权证明对应的 MOD 版本已不存在");
        }
        Object rawValue = versionRow.get("manifest_json");
        Object keyIdValue = versionRow.get("publisher_key_id");
        Object signatureValue = versionRow.get("publisher_signature");
        if (rawValue == null || keyIdValue == null || signatureValue == null) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "授权证明对应版本缺少 Publisher 签名信息");
        }
        String rawManifest = rawValue.toString();
        String publisherKeyId = keyIdValue.toString();
        if (!publisherKeyId.equals(requiredText(claims, "publisherKeyId"))
                || !ManifestIntegrity.sha256(rawManifest).equals(requiredText(claims, "manifestSha256"))) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "授权证明对应的发布内容或 Publisher 密钥已变化");
        }
        // This checks the Publisher key's current database status as well as the signature.
        publisherKeys.verifyManifest(requiredText(claims, "publisherId"), publisherKeyId,
                signatureValue.toString(), rawManifest);

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("active", true);
        result.put("proofType", "MOD_CAPABILITY_AUTHORIZATION");
        result.put("modId", modId);
        result.put("version", version);
        result.put("capability", capability);
        result.put("manifestSha256", claims.get("manifestSha256"));
        result.put("publisherId", claims.get("publisherId"));
        result.put("expiresAt", claims.get("exp"));
        result.put("jti", claims.get("jti"));
        return result;
    }

    private static String requiredText(Map<String, Object> values, String name) {
        Object value = values.get(name);
        if (!(value instanceof String text) || text.isBlank()) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "授权证明缺少有效字段: " + name);
        }
        return text;
    }

    private static long requiredRevision(Map<String, Object> values, String name) {
        Object value = values.get(name);
        if (!(value instanceof Number number) || number.longValue() < 1) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "授权证明缺少有效授权版本号: " + name);
        }
        return number.longValue();
    }

    public Map<String, Object> publicKey(String keyId) { return signer.publicKey(keyId); }

    public Map<String, Object> publicKeys() { return signer.publicKeys(); }
}
