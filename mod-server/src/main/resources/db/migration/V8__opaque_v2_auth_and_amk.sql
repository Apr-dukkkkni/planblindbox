-- OPAQUE RFC 9807 authentication and client-wrapped account master keys.
-- Existing V1 password hashes are retained only for diagnostics/rollback;
-- V2 authentication never reads them and new OPAQUE accounts use NULL.
ALTER TABLE community_user MODIFY password_hash VARCHAR(255) NULL;

CREATE TABLE user_opaque_credential (
  user_id BIGINT NOT NULL PRIMARY KEY,
  registration_record LONGTEXT NOT NULL,
  wrapped_amk_json LONGTEXT NOT NULL,
  server_static_public_key VARCHAR(1024) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_opaque_credential_user FOREIGN KEY (user_id)
    REFERENCES community_user(user_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


CREATE TABLE opaque_registration_challenge (
  challenge_id CHAR(36) NOT NULL PRIMARY KEY,
  email VARCHAR(100) NOT NULL,
  username VARCHAR(50) NOT NULL,
  gender VARCHAR(20) NOT NULL,
  server_static_public_key VARCHAR(1024) NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  consumed_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_opaque_registration_email (email),
  KEY idx_opaque_registration_expiry (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE opaque_login_challenge (
  challenge_id CHAR(36) NOT NULL PRIMARY KEY,
  user_id BIGINT NULL,
  expires_at TIMESTAMP NOT NULL,
  consumed_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_opaque_challenge_user (user_id),
  KEY idx_opaque_challenge_expiry (expires_at),
  CONSTRAINT fk_opaque_challenge_user FOREIGN KEY (user_id)
    REFERENCES community_user(user_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
