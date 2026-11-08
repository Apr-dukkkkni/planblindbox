package com.planblindbox.mod.auth;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.Base64;
import java.util.Map;
import org.h2.jdbcx.JdbcDataSource;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.server.ResponseStatusException;

class OpaqueCredentialChangeTest {
    private static final long USER_ID = 42L;
    private static final String OPAQUE_ID = "a".repeat(32);
    private static final String PUBLIC_KEY = "test-server-public-key";
    private static final String CHALLENGE_ID = "123e4567-e89b-12d3-a456-426614174000";
    private static final String LOGIN_CHALLENGE_ID = "123e4567-e89b-12d3-a456-426614174001";
    private static final String CHANGE_TICKET = "b".repeat(43);

    private JdbcTemplate jdbc;
    private UserRepository users;
    private OpaqueProtocolClient opaque;
    private TokenService tokens;
    private OpaqueAuthController controller;
    private TransactionTemplate transaction;
    private final ObjectMapper mapper = new ObjectMapper();

    @BeforeEach
    void setUp() {
        JdbcDataSource dataSource = new JdbcDataSource();
        dataSource.setURL("jdbc:h2:mem:opaque_change_" + System.nanoTime()
            + ";MODE=MySQL;DB_CLOSE_DELAY=-1;DATABASE_TO_LOWER=TRUE");
        dataSource.setUser("sa");
        jdbc = new JdbcTemplate(dataSource);
        transaction = new TransactionTemplate(new DataSourceTransactionManager(dataSource));

        jdbc.execute("""
            CREATE TABLE community_user (
              user_id BIGINT PRIMARY KEY,
              username VARCHAR(50) NOT NULL,
              email VARCHAR(100) NOT NULL,
              password_hash VARCHAR(255),
              gender VARCHAR(20) NOT NULL,
              avatar VARCHAR(500),
              birthday DATE,
              status VARCHAR(20) NOT NULL,
              credential_version BIGINT NOT NULL DEFAULT 0,
              last_login_at TIMESTAMP
            )
            """);
        jdbc.execute("""
            CREATE TABLE user_opaque_credential (
              user_id BIGINT PRIMARY KEY,
              opaque_user_identifier VARCHAR(64) NOT NULL,
              registration_record CLOB NOT NULL,
              wrapped_amk_json CLOB NOT NULL,
              server_static_public_key VARCHAR(1024) NOT NULL,
              created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
              updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """);
        jdbc.execute("""
            CREATE TABLE opaque_login_challenge (
              challenge_id CHAR(36) PRIMARY KEY,
              user_id BIGINT,
              credential_version BIGINT,
              expires_at TIMESTAMP NOT NULL,
              consumed_at TIMESTAMP,
              created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """);
        jdbc.execute("""
            CREATE TABLE opaque_credential_change_ticket (
              ticket_hash CHAR(64) PRIMARY KEY,
              user_id BIGINT NOT NULL,
              credential_version BIGINT NOT NULL,
              expires_at TIMESTAMP NOT NULL,
              consumed_at TIMESTAMP,
              created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """);
        jdbc.execute("""
            CREATE TABLE opaque_credential_change_challenge (
              challenge_id CHAR(36) PRIMARY KEY,
              user_id BIGINT NOT NULL,
              opaque_user_identifier VARCHAR(64) NOT NULL,
              credential_version BIGINT NOT NULL,
              server_static_public_key VARCHAR(1024) NOT NULL,
              expires_at TIMESTAMP NOT NULL,
              consumed_at TIMESTAMP,
              created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """);
        jdbc.update("""
            INSERT INTO community_user
              (user_id,username,email,password_hash,gender,status,credential_version)
            VALUES (?,?,?,?,?,?,?)
            """, USER_ID, "tester", "tester@example.com", null, "UNDISCLOSED", "ACTIVE", 7L);
        jdbc.update("""
            INSERT INTO user_opaque_credential
              (user_id,opaque_user_identifier,registration_record,wrapped_amk_json,server_static_public_key)
            VALUES (?,?,?,?,?)
            """, USER_ID, OPAQUE_ID, "old-registration-record",
            validEnvelope().toString(), PUBLIC_KEY);

        users = new UserRepository(jdbc);
        opaque = mock(OpaqueProtocolClient.class);
        tokens = mock(TokenService.class);
        when(tokens.ttl()).thenReturn(7200L);
        controller = new OpaqueAuthController(users, tokens, opaque, jdbc, mapper);
    }

    @Test
    void successfulOpaqueLoginIssuesSingleUseCredentialChangeTicket() {
        jdbc.update("""
            INSERT INTO opaque_login_challenge
              (challenge_id,user_id,credential_version,expires_at)
            VALUES (?,?,?,?)
            """, LOGIN_CHALLENGE_ID, USER_ID, 7L,
            Timestamp.from(Instant.now().plusSeconds(120)));
        when(tokens.issue(any(UserRepository.User.class))).thenReturn("login-access-token");

        OpaqueAuthController.LoginResponse response = transaction.execute(status ->
            controller.loginFinish(
                new OpaqueAuthController.LoginFinish(LOGIN_CHALLENGE_ID, "opaque-finish-request")));

        assertEquals("login-access-token", response.accessToken());
        assertNotNull(response.credentialChangeTicket());
        assertTrue(response.credentialChangeTicket().matches("[A-Za-z0-9_-]{43}"));
        assertEquals(1, jdbc.queryForObject(
            "SELECT COUNT(*) FROM opaque_credential_change_ticket WHERE user_id=? " +
            "AND ticket_hash=? AND credential_version=7",
            Integer.class, USER_ID, ticketHash(response.credentialChangeTicket())));
        verify(opaque).loginFinish(LOGIN_CHALLENGE_ID, "opaque-finish-request");
    }

    @Test
    void startUsesStableOpaqueIdentifierAndCreatesShortLivedChallenge() {
        insertTicket(USER_ID, 7L, Instant.now().plusSeconds(120));
        when(opaque.serverPublicKey()).thenReturn(PUBLIC_KEY);
        when(opaque.registrationStart(OPAQUE_ID, "new-registration-request"))
            .thenReturn(Map.of(
                "registrationResponse", "server-registration-response",
                "serverStaticPublicKey", PUBLIC_KEY));

        Map<String, Object> response = transaction.execute(status ->
            controller.credentialChangeStart(
                new OpaqueAuthController.CredentialChangeStart(
                    "new-registration-request", CHANGE_TICKET),
                jwt(USER_ID, Instant.now())));

        assertEquals(OPAQUE_ID, response.get("clientIdentifier"));
        assertNotNull(response.get("challengeId"));
        assertEquals("server-registration-response", response.get("registrationResponse"));
        assertEquals(1, jdbc.queryForObject(
            "SELECT COUNT(*) FROM opaque_credential_change_challenge WHERE user_id=?",
            Integer.class, USER_ID));
        verify(opaque).registrationStart(OPAQUE_ID, "new-registration-request");
        assertNotNull(jdbc.queryForObject(
            "SELECT consumed_at FROM opaque_credential_change_ticket WHERE ticket_hash=?",
            Timestamp.class, ticketHash(CHANGE_TICKET)));
        ResponseStatusException replay = assertThrows(ResponseStatusException.class,
            () -> transaction.execute(status -> controller.credentialChangeStart(
                new OpaqueAuthController.CredentialChangeStart(
                    "another-registration-request", CHANGE_TICKET),
                jwt(USER_ID, Instant.now()))));
        assertEquals(HttpStatus.UNAUTHORIZED, replay.getStatusCode());
    }

    @Test
    void startRejectsExpiredCredentialChangeTicket() {
        insertTicket(USER_ID, 7L, Instant.now().minusSeconds(1));

        ResponseStatusException error = assertThrows(ResponseStatusException.class,
            () -> transaction.execute(status -> controller.credentialChangeStart(
                new OpaqueAuthController.CredentialChangeStart(
                    "new-registration-request", CHANGE_TICKET),
                jwt(USER_ID, Instant.now()))));

        assertEquals(HttpStatus.UNAUTHORIZED, error.getStatusCode());
        assertEquals(0, jdbc.queryForObject(
            "SELECT COUNT(*) FROM opaque_credential_change_challenge", Integer.class));
        verifyNoInteractions(opaque);
    }

    @Test
    void startRejectsStaleAuthenticationBeforeCreatingChallenge() {
        ResponseStatusException error = assertThrows(ResponseStatusException.class,
            () -> transaction.execute(status -> controller.credentialChangeStart(
                new OpaqueAuthController.CredentialChangeStart(
                    "new-registration-request", CHANGE_TICKET),
                jwt(USER_ID, Instant.now().minusSeconds(301)))));

        assertEquals(HttpStatus.UNAUTHORIZED, error.getStatusCode());
        assertEquals(0, jdbc.queryForObject(
            "SELECT COUNT(*) FROM opaque_credential_change_challenge", Integer.class));
        verifyNoInteractions(opaque);
    }

    @Test
    void finishAtomicallyReplacesCredentialAndRevokesOldTokens() {
        insertChallenge(USER_ID, 7L, Instant.now().plusSeconds(120));
        when(opaque.serverPublicKey()).thenReturn(PUBLIC_KEY);
        when(tokens.issue(any(UserRepository.User.class))).thenReturn("fresh-access-token");
        JsonNode newEnvelope = validEnvelope();

        OpaqueAuthController.CredentialChangeResponse response =
            transaction.execute(status -> controller.credentialChangeFinish(
                new OpaqueAuthController.CredentialChangeFinish(
                    CHALLENGE_ID, "new-registration-record", PUBLIC_KEY, newEnvelope),
                jwt(USER_ID, Instant.now())));

        assertEquals("fresh-access-token", response.accessToken());
        assertEquals(7200L, response.expiresIn());
        assertEquals("new-registration-record", jdbc.queryForObject(
            "SELECT registration_record FROM user_opaque_credential WHERE user_id=?",
            String.class, USER_ID));
        assertEquals(newEnvelope.toString(), jdbc.queryForObject(
            "SELECT wrapped_amk_json FROM user_opaque_credential WHERE user_id=?",
            String.class, USER_ID));
        assertEquals(8L, jdbc.queryForObject(
            "SELECT credential_version FROM community_user WHERE user_id=?",
            Long.class, USER_ID));
        assertNotNull(jdbc.queryForObject(
            "SELECT consumed_at FROM opaque_credential_change_challenge WHERE challenge_id=?",
            Timestamp.class, CHALLENGE_ID));
        verify(tokens).issue(argThat(user -> user.id() == USER_ID
            && user.credentialVersion() == 8L));

        com.planblindbox.mod.domain.BadRequest replay = assertThrows(com.planblindbox.mod.domain.BadRequest.class,
            () -> transaction.execute(status -> controller.credentialChangeFinish(
                new OpaqueAuthController.CredentialChangeFinish(
                    CHALLENGE_ID, "another-registration-record", PUBLIC_KEY, newEnvelope),
                jwt(USER_ID, Instant.now()))));
        assertNotNull(replay.getMessage());
    }

    @Test
    void finishRollsBackCredentialAndRevocationIfTokenIssuanceFails() {
        insertChallenge(USER_ID, 7L, Instant.now().plusSeconds(120));
        when(opaque.serverPublicKey()).thenReturn(PUBLIC_KEY);
        when(tokens.issue(any(UserRepository.User.class)))
            .thenThrow(new IllegalStateException("simulated token signer failure"));

        assertThrows(IllegalStateException.class,
            () -> transaction.execute(status -> controller.credentialChangeFinish(
                new OpaqueAuthController.CredentialChangeFinish(
                    CHALLENGE_ID, "new-registration-record", PUBLIC_KEY, validEnvelope()),
                jwt(USER_ID, Instant.now()))));

        assertEquals("old-registration-record", jdbc.queryForObject(
            "SELECT registration_record FROM user_opaque_credential WHERE user_id=?",
            String.class, USER_ID));
        assertEquals(7L, jdbc.queryForObject(
            "SELECT credential_version FROM community_user WHERE user_id=?",
            Long.class, USER_ID));
        assertNull(jdbc.queryForObject(
            "SELECT consumed_at FROM opaque_credential_change_challenge WHERE challenge_id=?",
            Timestamp.class, CHALLENGE_ID));
    }

    @Test
    void finishRejectsChallengeCreatedAgainstOlderCredentialVersion() {
        insertChallenge(USER_ID, 6L, Instant.now().plusSeconds(120));
        when(opaque.serverPublicKey()).thenReturn(PUBLIC_KEY);

        ResponseStatusException error = assertThrows(ResponseStatusException.class,
            () -> transaction.execute(status -> controller.credentialChangeFinish(
                new OpaqueAuthController.CredentialChangeFinish(
                    CHALLENGE_ID, "new-registration-record", PUBLIC_KEY, validEnvelope()),
                jwt(USER_ID, Instant.now()))));

        assertEquals(HttpStatus.CONFLICT, error.getStatusCode());
        assertEquals("old-registration-record", jdbc.queryForObject(
            "SELECT registration_record FROM user_opaque_credential WHERE user_id=?",
            String.class, USER_ID));
        assertEquals(7L, jdbc.queryForObject(
            "SELECT credential_version FROM community_user WHERE user_id=?",
            Long.class, USER_ID));
    }

    @Test
    void finishRejectsAnotherAccountsChallenge() {
        insertChallenge(USER_ID + 1, 7L, Instant.now().plusSeconds(120));

        ResponseStatusException error = assertThrows(ResponseStatusException.class,
            () -> transaction.execute(status -> controller.credentialChangeFinish(
                new OpaqueAuthController.CredentialChangeFinish(
                    CHALLENGE_ID, "new-registration-record", PUBLIC_KEY, validEnvelope()),
                jwt(USER_ID, Instant.now()))));

        assertEquals(HttpStatus.FORBIDDEN, error.getStatusCode());
    }

    @Test
    void finishRejectsExpiredChallengeAndMalformedEnvelope() {
        insertChallenge(USER_ID, 7L, Instant.now().minusSeconds(1));
        when(opaque.serverPublicKey()).thenReturn(PUBLIC_KEY);

        com.planblindbox.mod.domain.BadRequest expired = assertThrows(com.planblindbox.mod.domain.BadRequest.class,
            () -> transaction.execute(status -> controller.credentialChangeFinish(
                new OpaqueAuthController.CredentialChangeFinish(
                    CHALLENGE_ID, "new-registration-record", PUBLIC_KEY, validEnvelope()),
                jwt(USER_ID, Instant.now()))));
        assertNotNull(expired.getMessage());

        JsonNode malformed = mapper.createObjectNode()
            .put("version", 2)
            .put("kdf", "hkdf-sha256")
            .put("alg", "aes-256-gcm")
            .put("salt", Base64.getEncoder().encodeToString(new byte[16]))
            .put("nonce", Base64.getEncoder().encodeToString(new byte[12]))
            .put("ciphertext", Base64.getEncoder().encodeToString(new byte[31]))
            .put("tag", Base64.getEncoder().encodeToString(new byte[16]));
        assertThrows(RuntimeException.class, () -> transaction.execute(status ->
            controller.credentialChangeFinish(
                new OpaqueAuthController.CredentialChangeFinish(
                    CHALLENGE_ID, "new-registration-record", PUBLIC_KEY, malformed),
                jwt(USER_ID, Instant.now()))));
    }

    private void insertTicket(long userId, long credentialVersion, Instant expiry) {
        jdbc.update("""
            INSERT INTO opaque_credential_change_ticket
              (ticket_hash,user_id,credential_version,expires_at)
            VALUES (?,?,?,?)
            """, ticketHash(CHANGE_TICKET), userId, credentialVersion,
            Timestamp.from(expiry));
    }

    private String ticketHash(String ticket) {
        try {
            byte[] digest = java.security.MessageDigest.getInstance("SHA-256")
                .digest(ticket.getBytes(java.nio.charset.StandardCharsets.US_ASCII));
            return java.util.HexFormat.of().formatHex(digest);
        } catch (Exception error) {
            throw new IllegalStateException(error);
        }
    }

    private void insertChallenge(long userId, long credentialVersion, Instant expiry) {
        jdbc.update("""
            INSERT INTO opaque_credential_change_challenge
              (challenge_id,user_id,opaque_user_identifier,credential_version,
               server_static_public_key,expires_at)
            VALUES (?,?,?,?,?,?)
            """, CHALLENGE_ID, userId, OPAQUE_ID, credentialVersion, PUBLIC_KEY,
            Timestamp.from(expiry));
    }

    private Jwt jwt(long userId, Instant issuedAt) {
        return Jwt.withTokenValue("test-token")
            .header("alg", "HS256")
            .subject(Long.toString(userId))
            .issuedAt(issuedAt)
            .expiresAt(issuedAt.plusSeconds(7200))
            .claim("cv", 7L)
            .build();
    }

    private JsonNode validEnvelope() {
        return mapper.createObjectNode()
            .put("version", 2)
            .put("kdf", "hkdf-sha256")
            .put("alg", "aes-256-gcm")
            .put("salt", Base64.getEncoder().encodeToString(new byte[16]))
            .put("nonce", Base64.getEncoder().encodeToString(new byte[12]))
            .put("ciphertext", Base64.getEncoder().encodeToString(new byte[32]))
            .put("tag", Base64.getEncoder().encodeToString(new byte[16]));
    }
}
