-- Immutable per-account KDF setup. The recovery phrase and derived AES key
-- never pass through this database. Existing V6 data remains untouched.
CREATE TABLE user_sync_crypto_config (
  user_id BIGINT NOT NULL PRIMARY KEY,
  salt_base64 VARCHAR(128) NOT NULL,
  iterations INT NOT NULL,
  verifier_json TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES community_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
