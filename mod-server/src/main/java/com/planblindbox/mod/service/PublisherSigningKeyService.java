package com.planblindbox.mod.service;

import com.planblindbox.mod.domain.BadRequest;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.MessageDigest;
import java.security.PublicKey;
import java.security.Signature;
import java.security.spec.X509EncodedKeySpec;
import java.util.Base64;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * Publisher key enrollment and Ed25519 verification.
 * Public keys are enrolled by a platform administrator after out-of-band publisher verification.
 * The service deliberately does not treat a self-asserted publisher ID as an identity proof.
 */
@Service
public class PublisherSigningKeyService {
    private static final Pattern PUBLISHER_ID = Pattern.compile("^[a-z][a-z0-9]*(\\.[a-z][a-z0-9-]*)+$");
    private final JdbcTemplate jdbc;

    public PublisherSigningKeyService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public record EnrolledKey(String publisherId, String keyId, String status) {}

    @Transactional
    public Map<String, Object> enroll(String publisherId, String publicKeyBase64, String adminActor) {
        validatePublisherId(publisherId);
        if (publicKeyBase64 == null || publicKeyBase64.length() > 512) {
            throw new BadRequest("publicKeyBase64 缺失或过长");
        }
        final byte[] encoded;
        try {
            encoded = Base64.getDecoder().decode(publicKeyBase64);
            decodePublicKey(encoded); // Validate the X.509 SubjectPublicKeyInfo before persistence.
        } catch (IllegalArgumentException e) {
            throw new BadRequest("Ed25519 公钥必须是有效的 Base64 X.509 编码");
        }
        if (encoded.length != 44) throw new BadRequest("Ed25519 X.509 公钥长度不合法");
        String keyId = sha256Hex(encoded);
        List<Integer> existing = jdbc.query(
                "SELECT 1 FROM mod_publisher_signing_key WHERE key_id=?",
                (rs, row) -> rs.getInt(1), keyId);
        if (!existing.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "该公钥已登记，不能重复登记或重新激活");
        }
        jdbc.update("""
                INSERT INTO mod_publisher_signing_key
                  (publisher_id,key_id,public_key_x509,status,enrolled_by)
                VALUES (?,?,?,'ACTIVE',?)
                """, publisherId, keyId, publicKeyBase64, adminActor);
        jdbc.update("""
                INSERT INTO mod_publisher_signing_key_audit
                  (publisher_id,key_id,action,actor)
                VALUES (?,?,'ENROLLED',?)
                """, publisherId, keyId, adminActor);
        return Map.of("publisherId", publisherId, "keyId", keyId, "status", "ACTIVE", "algorithm", "Ed25519");
    }

    @Transactional
    public Map<String, Object> revoke(String publisherId, String keyId, String adminActor) {
        validatePublisherId(publisherId);
        if (keyId == null || !keyId.matches("[0-9a-f]{64}")) throw new BadRequest("keyId 格式错误");
        int changed = jdbc.update("""
                UPDATE mod_publisher_signing_key SET status='REVOKED',revoked_at=CURRENT_TIMESTAMP
                WHERE publisher_id=? AND key_id=? AND status='ACTIVE'
                """, publisherId, keyId);
        if (changed == 0) {
            List<Integer> exists = jdbc.query("SELECT 1 FROM mod_publisher_signing_key WHERE publisher_id=? AND key_id=?",
                    (rs, row) -> rs.getInt(1), publisherId, keyId);
            if (exists.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Publisher 公钥不存在");
            return Map.of("publisherId", publisherId, "keyId", keyId, "status", "REVOKED");
        }
        jdbc.update("INSERT INTO mod_publisher_signing_key_audit(publisher_id,key_id,action,actor) VALUES (?,?,'REVOKED',?)",
                publisherId, keyId, adminActor);
        return Map.of("publisherId", publisherId, "keyId", keyId, "status", "REVOKED");
    }

    public Map<String, Object> publicKey(String publisherId, String keyId) {
        validatePublisherId(publisherId);
        if (keyId == null || !keyId.matches("[0-9a-f]{64}")) throw new BadRequest("keyId 格式错误");
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT public_key_x509,status,revoked_at FROM mod_publisher_signing_key
                WHERE publisher_id=? AND key_id=?
                """, publisherId, keyId);
        if (rows.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Publisher 公钥不存在");
        String encoded = (String) rows.get(0).get("public_key_x509");
        byte[] keyBytes = Base64.getDecoder().decode(encoded);
        if (!keyId.equals(sha256Hex(keyBytes))) throw new ResponseStatusException(HttpStatus.CONFLICT, "Publisher 公钥指纹不匹配");
        Map<String, Object> result = new java.util.LinkedHashMap<>();
        result.put("publisherId", publisherId); result.put("keyId", keyId);
        result.put("algorithm", "Ed25519"); result.put("publicKeyX509Base64", encoded);
        result.put("status", rows.get(0).get("status")); result.put("revokedAt", rows.get(0).get("revoked_at"));
        return result;
    }

    public void verifyManifest(String publisherId, String keyId, String signatureBase64, String rawManifest) {
        validatePublisherId(publisherId);
        if (keyId == null || !keyId.matches("[0-9a-f]{64}") || signatureBase64 == null || signatureBase64.length() > 256) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "缺少有效的 Publisher 签名头");
        }
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT public_key_x509 FROM mod_publisher_signing_key
                WHERE publisher_id=? AND key_id=? AND status='ACTIVE'
                """, publisherId, keyId);
        if (rows.isEmpty()) throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Publisher 签名密钥不存在或已吊销");
        try {
            byte[] encodedKey = Base64.getDecoder().decode((String) rows.get(0).get("public_key_x509"));
            if (!keyId.equals(sha256Hex(encodedKey))) {
                throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Publisher 公钥指纹不匹配");
            }
            byte[] signatureBytes = Base64.getDecoder().decode(signatureBase64);
            if (signatureBytes.length != 64) throw new IllegalArgumentException("Invalid Ed25519 signature length");
            Signature verifier = Signature.getInstance("Ed25519");
            verifier.initVerify(decodePublicKey(encodedKey));
            verifier.update(rawManifest.getBytes(StandardCharsets.UTF_8));
            if (!verifier.verify(signatureBytes)) {
                throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Publisher Manifest 签名验证失败");
            }
        } catch (ResponseStatusException e) {
            throw e;
        } catch (Exception e) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Publisher Manifest 签名格式无效");
        }
    }

    private static PublicKey decodePublicKey(byte[] encoded) {
        try {
            return KeyFactory.getInstance("Ed25519").generatePublic(new X509EncodedKeySpec(encoded));
        } catch (Exception e) {
            throw new IllegalArgumentException("Invalid Ed25519 X.509 public key", e);
        }
    }

    private static String sha256Hex(byte[] bytes) {
        try { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)); }
        catch (Exception e) { throw new IllegalStateException("SHA-256 unavailable", e); }
    }

    private static void validatePublisherId(String publisherId) {
        if (publisherId == null || publisherId.length() > 100 || !PUBLISHER_ID.matcher(publisherId).matches()) {
            throw new BadRequest("Publisher ID 格式错误");
        }
    }
}
