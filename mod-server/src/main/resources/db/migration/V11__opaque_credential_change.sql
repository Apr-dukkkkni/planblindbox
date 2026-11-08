-- Bind pending OPAQUE login challenges to the credential version read at login/start.
-- A password change that races with an in-flight login invalidates that challenge.
ALTER TABLE opaque_login_challenge
  ADD COLUMN credential_version BIGINT NULL AFTER user_id;

-- One-time, short-lived proof issued only after a successful OPAQUE login.
-- The raw ticket is returned once to the client; only its SHA-256 hash is stored.
CREATE TABLE opaque_credential_change_ticket (
  ticket_hash CHAR(64) NOT NULL PRIMARY KEY,
  user_id BIGINT NOT NULL,
  credential_version BIGINT NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  consumed_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_opaque_change_ticket_user (user_id, consumed_at, expires_at),
  KEY idx_opaque_change_ticket_expiry (expires_at),
  CONSTRAINT fk_opaque_change_ticket_user FOREIGN KEY (user_id)
    REFERENCES community_user(user_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- One-time challenges for changing an existing OPAQUE credential.
-- No password, export key, or plaintext AMK is stored in this table.
CREATE TABLE opaque_credential_change_challenge (
  challenge_id CHAR(36) NOT NULL PRIMARY KEY,
  user_id BIGINT NOT NULL,
  opaque_user_identifier VARCHAR(64) NOT NULL,
  credential_version BIGINT NOT NULL,
  server_static_public_key VARCHAR(1024) NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  consumed_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_opaque_change_user (user_id, consumed_at, expires_at),
  KEY idx_opaque_change_expiry (expires_at),
  CONSTRAINT fk_opaque_change_user FOREIGN KEY (user_id)
    REFERENCES community_user(user_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
