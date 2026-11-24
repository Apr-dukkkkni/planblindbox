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
import org.springframework.web.server.ResponseStatusException;

import java.util.LinkedHashMap;
import java.util.Map;

@Service
public final class ModCapabilityProofService {
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

    public Map<String, Object> publicKey(String keyId) { return signer.publicKey(keyId); }
}
