CREATE TABLE mod_publisher_signing_key (
  key_id CHAR(64) NOT NULL PRIMARY KEY,
  publisher_id VARCHAR(100) NOT NULL,
  public_key_x509 VARCHAR(512) NOT NULL,
  status VARCHAR(16) NOT NULL,
  enrolled_by VARCHAR(100) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  revoked_at TIMESTAMP NULL,
  CONSTRAINT uk_publisher_signing_key UNIQUE (publisher_id, key_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE mod_publisher_signing_key_audit (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  publisher_id VARCHAR(100) NOT NULL,
  key_id CHAR(64) NOT NULL,
  action VARCHAR(16) NOT NULL,
  actor VARCHAR(100) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_publisher_key_audit (publisher_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE INDEX idx_publisher_signing_key_status
  ON mod_publisher_signing_key(publisher_id, status);

ALTER TABLE mod_versions
    ADD COLUMN publisher_key_id CHAR(64) NULL;

ALTER TABLE mod_versions
    ADD COLUMN publisher_signature VARCHAR(128) NULL;
