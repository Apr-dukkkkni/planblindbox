-- Per-user serialized mutation stream; the cursor is scoped to one account.
CREATE TABLE user_sync_clock (
  user_id BIGINT PRIMARY KEY,
  cursor BIGINT NOT NULL DEFAULT 0,
  FOREIGN KEY (user_id) REFERENCES community_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- A paid entitlement is provisioned only after payment verification (no client-side grant API).
CREATE TABLE user_sync_entitlement (
  user_id BIGINT PRIMARY KEY,
  expires_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES community_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE user_sync_record (
  user_id BIGINT NOT NULL,
  record_type VARCHAR(32) NOT NULL,
  record_id VARCHAR(80) NOT NULL,
  revision BIGINT NOT NULL,
  deleted BOOLEAN NOT NULL DEFAULT FALSE,
  payload TEXT NULL,
  changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, record_type, record_id),
  FOREIGN KEY (user_id) REFERENCES community_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE user_sync_change (
  user_id BIGINT NOT NULL,
  cursor BIGINT NOT NULL,
  record_type VARCHAR(32) NOT NULL,
  record_id VARCHAR(80) NOT NULL,
  revision BIGINT NOT NULL,
  deleted BOOLEAN NOT NULL,
  payload TEXT NULL,
  changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, cursor),
  KEY idx_sync_change_record(user_id, record_type, record_id),
  FOREIGN KEY (user_id) REFERENCES community_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Retries must reuse operationId. A recorded result makes network retries exactly-once.
CREATE TABLE user_sync_operation (
  user_id BIGINT NOT NULL,
  operation_id VARCHAR(64) NOT NULL,
  record_type VARCHAR(32) NOT NULL,
  record_id VARCHAR(80) NOT NULL,
  revision BIGINT NOT NULL,
  cursor BIGINT NOT NULL,
  request_hash CHAR(64) NOT NULL,
  PRIMARY KEY (user_id, operation_id),
  FOREIGN KEY (user_id) REFERENCES community_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
