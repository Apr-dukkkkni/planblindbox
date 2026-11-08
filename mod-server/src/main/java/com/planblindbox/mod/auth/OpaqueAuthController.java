package com.planblindbox.mod.auth;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.planblindbox.mod.domain.BadRequest;
import java.time.Instant;
import java.sql.Timestamp;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.HexFormat;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

/** OPAQUE-only account registration and login endpoints for protocol V2. */
@RestController
@RequestMapping("/api/v2/auth")
public class OpaqueAuthController {
    public record RegistrationStart(String username, String email, String gender,
                                    String registrationRequest) {}
    public record RegistrationFinish(String challengeId, String username, String email, String gender,
            String registrationRecord, String serverStaticPublicKey, JsonNode wrappedAmk) {}
    public record LoginStart(String email, String startLoginRequest) {}
    public record LoginFinish(String challengeId, String finishLoginRequest) {}
    public record LoginResponse(String accessToken, long expiresIn,
            AuthService.Profile user, JsonNode wrappedAmk, String serverStaticPublicKey,
            String credentialChangeTicket) {}
    public record CredentialChangeStart(String registrationRequest,
            String credentialChangeTicket) {}
    public record CredentialChangeFinish(String challengeId, String registrationRecord,
            String serverStaticPublicKey, JsonNode wrappedAmk) {}
    public record CredentialChangeResponse(String accessToken, long expiresIn) {}
    private record CredentialChangeChallenge(long userId, String opaqueUserIdentifier,
            long credentialVersion, String serverStaticPublicKey,
            Timestamp expiresAt, Timestamp consumedAt) {}

    private final UserRepository users;
    private final TokenService tokens;
    private final OpaqueProtocolClient opaque;
    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper;
    private final SecureRandom random = new SecureRandom();

    public OpaqueAuthController(UserRepository users, TokenService tokens,
            OpaqueProtocolClient opaque, JdbcTemplate jdbc, ObjectMapper mapper) {
        this.users = users;
        this.tokens = tokens;
        this.opaque = opaque;
        this.jdbc = jdbc;
        this.mapper = mapper;
    }

    @PostMapping("/register/start")
    public Map<String, Object> registrationStart(@RequestBody RegistrationStart request) {
        if (request == null) throw new BadRequest("注册信息无效");
        String email = PasswordRules.email(request.email());
        PasswordRules.username(request.username());
        PasswordRules.gender(request.gender());
        requireProtocolMessage(request.registrationRequest(), 200000, "OPAQUE 注册请求");
        if (users.byEmail(email) != null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "该邮箱已经注册");
        }
        jdbc.update("DELETE FROM opaque_registration_challenge WHERE expires_at<NOW() OR " +
            "(consumed_at IS NOT NULL AND created_at<DATE_SUB(NOW(),INTERVAL 1 DAY))");
        Integer pending = jdbc.queryForObject("SELECT COUNT(*) FROM opaque_registration_challenge " +
            "WHERE email=? AND consumed_at IS NULL AND expires_at>NOW()", Integer.class, email);
        if (pending != null && pending >= 5) {
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS, "注册请求过于频繁，请稍后再试");
        }
        String opaqueIdentifier = java.util.UUID.randomUUID().toString().replace("-", "");
        Map<String, Object> response = opaque.registrationStart(opaqueIdentifier, request.registrationRequest());
        String publicKey = String.valueOf(response.get("serverStaticPublicKey"));
        String challengeId = java.util.UUID.randomUUID().toString();
        jdbc.update("INSERT INTO opaque_registration_challenge " +
            "(challenge_id,email,opaque_user_identifier,username,gender,server_static_public_key,expires_at) " +
            "VALUES(?,?,?,?,?,?,DATE_ADD(NOW(),INTERVAL 5 MINUTE))",
            challengeId, email, opaqueIdentifier, PasswordRules.username(request.username()),
            PasswordRules.gender(request.gender()), publicKey);
        return Map.of(
            "challengeId", challengeId,
            "clientIdentifier", opaqueIdentifier,
            "registrationResponse", response.get("registrationResponse"),
            "serverStaticPublicKey", publicKey);
    }

    @PostMapping("/register/finish")
    @Transactional
    public AuthService.Profile registrationFinish(@RequestBody RegistrationFinish request) {
        if (request == null) throw new BadRequest("注册信息无效");
        String email = PasswordRules.email(request.email());
        String username = PasswordRules.username(request.username());
        String gender = PasswordRules.gender(request.gender());
        requireProtocolMessage(request.registrationRecord(), 200000, "OPAQUE 注册凭据");
        validateWrappedAmk(request.wrappedAmk());
        if (request.challengeId() == null ||
            !request.challengeId().matches("[0-9a-fA-F-]{36}")) {
            throw new BadRequest("注册挑战无效或已过期");
        }
        var challengeRows = jdbc.query("SELECT email,opaque_user_identifier,username,gender,server_static_public_key " +
            "FROM opaque_registration_challenge WHERE challenge_id=? AND consumed_at IS NULL " +
            "AND expires_at>NOW() FOR UPDATE", (rs, i) -> new String[]{
                rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5)}, request.challengeId());
        if (challengeRows.isEmpty()) throw new BadRequest("注册挑战无效或已过期");
        String[] challenge = challengeRows.get(0);
        if (!challenge[0].equals(email) || !challenge[2].equals(username) ||
            !challenge[3].equals(gender) || !challenge[4].equals(request.serverStaticPublicKey())) {
            throw new BadRequest("注册信息与 OPAQUE 挑战不匹配");
        }
        String expectedPublicKey = opaque.serverPublicKey();
        if (!expectedPublicKey.equals(request.serverStaticPublicKey())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "OPAQUE 服务端公钥不匹配，已拒绝注册");
        }
        if (users.lockEmail(email) != null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "该邮箱已经注册");
        }
        long id = users.insertOpaque(username, email, gender);
        users.insertOpaqueCredential(id, challenge[1], request.registrationRecord(),
            request.wrappedAmk().toString(), expectedPublicKey);
        jdbc.update("UPDATE opaque_registration_challenge SET consumed_at=NOW() WHERE challenge_id=?",
            request.challengeId());
        return AuthService.profile(users.byId(id));
    }

    @PostMapping("/login/start")
    public Map<String, Object> loginStart(@RequestBody LoginStart request) {
        if (request == null) throw new BadRequest("登录信息无效");
        String email = PasswordRules.email(request.email());
        requireProtocolMessage(request.startLoginRequest(), 200000, "OPAQUE 登录请求");
        jdbc.update("DELETE FROM opaque_login_challenge WHERE expires_at<NOW() OR " +
            "(consumed_at IS NOT NULL AND created_at<DATE_SUB(NOW(),INTERVAL 1 DAY))");
        Integer pending = jdbc.queryForObject("SELECT COUNT(*) FROM opaque_login_challenge " +
            "WHERE user_id IS NOT NULL AND user_id=(SELECT user_id FROM community_user WHERE email=?) " +
            "AND consumed_at IS NULL AND expires_at>NOW()", Integer.class, email);
        if (pending != null && pending >= 5) {
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS, "登录请求过于频繁，请稍后再试");
        }
        UserRepository.User user = users.byEmail(email);
        UserRepository.OpaqueCredential credential = user == null || !"ACTIVE".equals(user.status())
            ? null : users.opaqueCredential(user.id());
        // Unknown/legacy accounts receive a decoy OPAQUE response so the
        // first round-trip does not reveal whether an email exists.
        String clientIdentifier = credential == null ? "00000000000000000000000000000000"
            : credential.opaqueUserIdentifier();
        String record = credential == null ? opaque.decoyRegistrationRecord()
            : credential.registrationRecord();
        Map<String, Object> response = opaque.loginStart(clientIdentifier, record,
            request.startLoginRequest());
        String challengeId = String.valueOf(response.get("challengeId"));
        Long userId = credential == null ? null : user.id();
        Long credentialVersion = credential == null ? null : user.credentialVersion();
        jdbc.update("INSERT INTO opaque_login_challenge " +
            "(challenge_id,user_id,credential_version,expires_at) " +
            "VALUES(?,?,?,DATE_ADD(NOW(),INTERVAL 2 MINUTE))",
            challengeId, userId, credentialVersion);
        String publicKey = credential == null ? opaque.serverPublicKey()
            : credential.serverStaticPublicKey();
        return Map.of(
            "challengeId", challengeId,
            "clientIdentifier", clientIdentifier,
            "loginResponse", response.get("loginResponse"),
            "serverStaticPublicKey", publicKey);
    }

    @PostMapping("/login/finish")
    @Transactional
    public LoginResponse loginFinish(@RequestBody LoginFinish request) {
        if (request == null || request.challengeId() == null ||
            !request.challengeId().matches("[0-9a-fA-F-]{36}")) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "邮箱或密码错误");
        }
        requireProtocolMessage(request.finishLoginRequest(), 200000, "OPAQUE 登录完成消息");
        var rows = jdbc.query("SELECT user_id,credential_version FROM opaque_login_challenge " +
            "WHERE challenge_id=? AND consumed_at IS NULL AND expires_at>NOW() FOR UPDATE",
            (rs, i) -> new Object[] { rs.getObject(1), rs.getObject(2) },
            request.challengeId());
        if (rows.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "邮箱或密码错误");
        }
        Object[] challenge = rows.get(0);
        Long userId = challenge[0] == null ? null : ((Number) challenge[0]).longValue();
        if (userId == null) {
            // Unknown accounts receive a decoy OPAQUE exchange and never get
            // an access token or a credential-change ticket.
            opaque.loginFinish(request.challengeId(), request.finishLoginRequest());
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "邮箱或密码错误");
        }
        Long challengeVersion = challenge[1] == null
            ? null : ((Number) challenge[1]).longValue();
        // Lock the account row so a concurrent password change cannot race
        // between checking the login challenge and issuing its token/ticket.
        UserRepository.User user = users.lockById(userId);
        if (user == null || !"ACTIVE".equals(user.status()) ||
            challengeVersion == null || user.credentialVersion() != challengeVersion) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "邮箱或密码错误");
        }
        opaque.loginFinish(request.challengeId(), request.finishLoginRequest());
        jdbc.update("UPDATE opaque_login_challenge SET consumed_at=NOW() WHERE challenge_id=?",
            request.challengeId());
        UserRepository.OpaqueCredential credential = users.opaqueCredential(userId);
        if (credential == null) throw new ResponseStatusException(HttpStatus.UNAUTHORIZED);
        users.loginAt(userId);
        JsonNode wrapped = parse(credential.wrappedAmkJson());
        String changeTicket = issueCredentialChangeTicket(user);
        return new LoginResponse(tokens.issue(user), tokens.ttl(),
            AuthService.profile(user), wrapped, credential.serverStaticPublicKey(),
            changeTicket);
    }

    /**
     * Starts a password change after a fresh OPAQUE login.
     *
     * The client creates a new OPAQUE registration request with the new
     * password. The server reuses the account's immutable OPAQUE identifier;
     * it never receives the password or the OPAQUE export key.
     */
    @PostMapping("/credential/change/start")
    @Transactional
    public Map<String, Object> credentialChangeStart(
            @RequestBody CredentialChangeStart request,
            @AuthenticationPrincipal Jwt jwt) {
        long userId = requireRecentAuthentication(jwt);
        if (request == null) throw new BadRequest("密码修改请求无效");
        requireProtocolMessage(request.registrationRequest(), 200000, "OPAQUE 新密码注册请求");

        UserRepository.User user = users.lockById(userId);
        if (user == null || !"ACTIVE".equals(user.status())) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "登录已失效");
        }
        UserRepository.OpaqueCredential credential = users.opaqueCredential(userId);
        if (credential == null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "账号缺少 OPAQUE 凭据，无法修改密码");
        }

        String ticketHash = hashCredentialChangeTicket(request.credentialChangeTicket());
        var ticketRows = jdbc.query(
            "SELECT credential_version,expires_at,consumed_at " +
            "FROM opaque_credential_change_ticket WHERE ticket_hash=? AND user_id=? FOR UPDATE",
            (rs, i) -> new Object[] {
                rs.getLong(1), rs.getTimestamp(2), rs.getTimestamp(3)
            }, ticketHash, userId);
        if (ticketRows.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED,
                "当前密码验证已过期，请重新输入当前密码");
        }
        Object[] ticket = ticketRows.get(0);
        if (ticket[2] != null || ticket[1] == null ||
            !((Timestamp) ticket[1]).toInstant().isAfter(Instant.now())) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED,
                "当前密码验证已过期，请重新输入当前密码");
        }
        if (((Number) ticket[0]).longValue() != user.credentialVersion()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "账号凭据已发生变化，请重新登录");
        }

        Timestamp now = Timestamp.from(Instant.now());
        Timestamp oldChallengeCutoff = Timestamp.from(now.toInstant().minusSeconds(86400));
        jdbc.update("DELETE FROM opaque_credential_change_challenge WHERE expires_at<? " +
            "OR (consumed_at IS NOT NULL AND created_at<?)", now, oldChallengeCutoff);
        Integer pending = jdbc.queryForObject(
            "SELECT COUNT(*) FROM opaque_credential_change_challenge " +
            "WHERE user_id=? AND consumed_at IS NULL AND expires_at>?",
            Integer.class, userId, now);
        if (pending != null && pending >= 3) {
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,
                "密码修改请求过于频繁，请稍后再试");
        }

        String expectedPublicKey = opaque.serverPublicKey();
        if (!expectedPublicKey.equals(credential.serverStaticPublicKey())) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "OPAQUE 服务端公钥与账号记录不一致，已拒绝修改");
        }
        Map<String, Object> response = opaque.registrationStart(
            credential.opaqueUserIdentifier(), request.registrationRequest());
        String responsePublicKey = String.valueOf(response.get("serverStaticPublicKey"));
        if (!expectedPublicKey.equals(responsePublicKey)) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "OPAQUE 服务端公钥不一致，已拒绝修改");
        }

        String challengeId = UUID.randomUUID().toString();
        jdbc.update("INSERT INTO opaque_credential_change_challenge " +
            "(challenge_id,user_id,opaque_user_identifier,credential_version," +
            "server_static_public_key,expires_at) VALUES(?,?,?,?,?,?)",
            challengeId, userId, credential.opaqueUserIdentifier(),
            user.credentialVersion(), expectedPublicKey,
            Timestamp.from(Instant.now().plusSeconds(300)));
        int ticketConsumed = jdbc.update(
            "UPDATE opaque_credential_change_ticket SET consumed_at=? " +
            "WHERE ticket_hash=? AND user_id=? AND consumed_at IS NULL",
            Timestamp.from(Instant.now()), ticketHash, userId);
        if (ticketConsumed != 1) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED,
                "当前密码验证已使用，请重新输入当前密码");
        }

        return Map.of(
            "challengeId", challengeId,
            "clientIdentifier", credential.opaqueUserIdentifier(),
            "registrationResponse", response.get("registrationResponse"),
            "serverStaticPublicKey", expectedPublicKey);
    }

    /**
     * Atomically replaces the OPAQUE registration record and AMK envelope.
     * The AMK itself is unchanged; only its wrapping key has changed.
     */
    @PostMapping("/credential/change/finish")
    @Transactional
    public CredentialChangeResponse credentialChangeFinish(
            @RequestBody CredentialChangeFinish request,
            @AuthenticationPrincipal Jwt jwt) {
        long userId = requireRecentAuthentication(jwt);
        if (request == null || request.challengeId() == null ||
            !request.challengeId().matches("[0-9a-fA-F-]{36}")) {
            throw new BadRequest("密码修改挑战无效或已过期");
        }
        requireProtocolMessage(request.registrationRecord(), 200000, "OPAQUE 新注册凭据");
        validateWrappedAmk(request.wrappedAmk());

        var challenges = jdbc.query(
            "SELECT user_id,opaque_user_identifier,credential_version," +
            "server_static_public_key,expires_at,consumed_at " +
            "FROM opaque_credential_change_challenge WHERE challenge_id=? FOR UPDATE",
            (rs, i) -> new CredentialChangeChallenge(
                rs.getLong(1), rs.getString(2), rs.getLong(3), rs.getString(4),
                rs.getTimestamp(5), rs.getTimestamp(6)),
            request.challengeId());
        if (challenges.isEmpty()) {
            throw new BadRequest("密码修改挑战无效或已过期");
        }
        CredentialChangeChallenge challenge = challenges.get(0);
        if (challenge.userId() != userId) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "密码修改挑战不属于当前账号");
        }
        if (challenge.consumedAt() != null ||
            challenge.expiresAt() == null ||
            !challenge.expiresAt().toInstant().isAfter(Instant.now())) {
            throw new BadRequest("密码修改挑战无效或已过期");
        }

        UserRepository.User user = users.lockById(userId);
        if (user == null || !"ACTIVE".equals(user.status())) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "登录已失效");
        }
        if (user.credentialVersion() != challenge.credentialVersion()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "账号凭据已发生变化，请重新登录后再修改密码");
        }

        UserRepository.OpaqueCredential credential = users.opaqueCredentialForUpdate(userId);
        if (credential == null ||
            !credential.opaqueUserIdentifier().equals(challenge.opaqueUserIdentifier())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "账号 OPAQUE 标识已变化，请重新登录");
        }
        String expectedPublicKey = opaque.serverPublicKey();
        if (!expectedPublicKey.equals(challenge.serverStaticPublicKey()) ||
            !expectedPublicKey.equals(credential.serverStaticPublicKey()) ||
            !expectedPublicKey.equals(request.serverStaticPublicKey())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "OPAQUE 服务端公钥不匹配，已拒绝修改");
        }

        int changed = users.replaceOpaqueCredentialAndRevoke(
            userId, challenge.opaqueUserIdentifier(), request.registrationRecord(),
            request.wrappedAmk().toString(), expectedPublicKey);
        if (changed != 1) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "账号凭据已发生变化，请重新登录后再修改密码");
        }
        Timestamp completedAt = Timestamp.from(Instant.now());
        jdbc.update("UPDATE opaque_credential_change_challenge SET consumed_at=? " +
            "WHERE challenge_id=? AND consumed_at IS NULL",
            completedAt, request.challengeId());
        jdbc.update("UPDATE opaque_credential_change_ticket SET consumed_at=? " +
            "WHERE user_id=? AND consumed_at IS NULL", completedAt, userId);

        UserRepository.User updated = users.byId(userId);
        return new CredentialChangeResponse(tokens.issue(updated), tokens.ttl());
    }

    private String issueCredentialChangeTicket(UserRepository.User user) {
        byte[] bytes = new byte[32];
        random.nextBytes(bytes);
        String ticket = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        Timestamp now = Timestamp.from(Instant.now());
        Timestamp oldCutoff = Timestamp.from(now.toInstant().minusSeconds(86400));
        jdbc.update("DELETE FROM opaque_credential_change_ticket WHERE expires_at<? " +
            "OR (consumed_at IS NOT NULL AND created_at<?)", now, oldCutoff);
        jdbc.update("INSERT INTO opaque_credential_change_ticket " +
            "(ticket_hash,user_id,credential_version,expires_at) VALUES(?,?,?,?)",
            hashCredentialChangeTicket(ticket), user.id(), user.credentialVersion(),
            Timestamp.from(now.toInstant().plusSeconds(300)));
        return ticket;
    }

    private String hashCredentialChangeTicket(String ticket) {
        if (ticket == null || !ticket.matches("[A-Za-z0-9_-]{43}")) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED,
                "当前密码验证无效，请重新输入当前密码");
        }
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                .digest(ticket.getBytes(StandardCharsets.US_ASCII));
            return HexFormat.of().formatHex(digest);
        } catch (Exception error) {
            throw new IllegalStateException("无法验证密码修改授权", error);
        }
    }

    private long requireRecentAuthentication(Jwt jwt) {
        if (jwt == null || jwt.getIssuedAt() == null) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "请重新输入当前密码");
        }
        Instant issuedAt = jwt.getIssuedAt();
        Instant now = Instant.now();
        if (issuedAt.isBefore(now.minusSeconds(300)) ||
            issuedAt.isAfter(now.plusSeconds(30))) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED,
                "请重新输入当前密码后再修改密码");
        }
        try {
            return Long.parseLong(jwt.getSubject());
        } catch (RuntimeException error) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "登录已失效");
        }
    }

    private void requireProtocolMessage(String value, int max, String label) {
        if (value == null || value.isBlank() || value.length() > max) {
            throw new BadRequest(label + "无效");
        }
    }

    private void validateWrappedAmk(JsonNode node) {
        if (node == null || !node.isObject() || node.toString().length() > 4096 ||
            node.size() != 7 || node.path("version").asInt(-1) != 2 ||
            !"hkdf-sha256".equals(node.path("kdf").asText()) ||
            !"aes-256-gcm".equals(node.path("alg").asText()) ||
            !validB64(node.path("salt").asText(), 16, 16) ||
            !validB64(node.path("nonce").asText(), 12, 12) ||
            !validB64(node.path("ciphertext").asText(), 32, 32) ||
            !validB64(node.path("tag").asText(), 16, 16)) {
            throw new BadRequest("账号主密钥包装信封无效");
        }
    }

    private boolean validB64(String value, int min, int max) {
        try {
            int length = Base64.getDecoder().decode(value).length;
            return length >= min && length <= max;
        } catch (Exception error) { return false; }
    }

    private JsonNode parse(String value) {
        try { return mapper.readTree(value); }
        catch (Exception error) {
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,
                "账号主密钥包装记录损坏");
        }
    }
}
