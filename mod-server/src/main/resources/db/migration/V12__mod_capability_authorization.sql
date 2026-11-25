-- Align persisted version columns with Manifest V1 SemVer 2.0 (up to 64 chars).
ALTER TABLE mod_download_events DROP FOREIGN KEY fk_download_version;
-- uk_mod_version also provides the leading-column index required by
-- fk_mod_versions_mod (mod_versions.mod_id -> mod_packages.mod_id).
-- Keep that FK valid while replacing the composite unique index.
ALTER TABLE mod_versions ADD INDEX idx_mod_versions_mod_id_v12 (mod_id);
ALTER TABLE mod_versions DROP INDEX uk_mod_version;
ALTER TABLE mod_versions MODIFY version VARCHAR(64) NOT NULL;
ALTER TABLE mod_versions ADD CONSTRAINT uk_mod_version UNIQUE (mod_id, version);
ALTER TABLE mod_versions DROP INDEX idx_mod_versions_mod_id_v12;
ALTER TABLE mod_download_events MODIFY version VARCHAR(64) NOT NULL;
ALTER TABLE mod_download_events ADD CONSTRAINT fk_download_version
  FOREIGN KEY (mod_id, version) REFERENCES mod_versions(mod_id, version);
ALTER TABLE mod_packages MODIFY latest_version VARCHAR(64) NOT NULL;

CREATE TABLE mod_capability_approval (
  mod_id VARCHAR(100) NOT NULL,
  version VARCHAR(64) NOT NULL,
  manifest_sha256 CHAR(64) NOT NULL,
  publisher_id VARCHAR(100) NOT NULL,
  capability VARCHAR(80) NOT NULL,
  approved BOOLEAN NOT NULL,
  decision_reason VARCHAR(500) NOT NULL DEFAULT '',
  decided_by VARCHAR(100) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (mod_id, version, manifest_sha256, capability),
  CONSTRAINT fk_cap_approval_version FOREIGN KEY (mod_id, version)
    REFERENCES mod_versions(mod_id, version) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE user_mod_capability_grant (
  user_id BIGINT NOT NULL,
  mod_id VARCHAR(100) NOT NULL,
  version VARCHAR(64) NOT NULL,
  manifest_sha256 CHAR(64) NOT NULL,
  capability VARCHAR(80) NOT NULL,
  granted BOOLEAN NOT NULL,
  granted_at TIMESTAMP NULL,
  revoked_at TIMESTAMP NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, mod_id, version, manifest_sha256, capability),
  CONSTRAINT fk_user_mod_grant_user FOREIGN KEY (user_id)
    REFERENCES community_user(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_user_mod_grant_version FOREIGN KEY (mod_id, version)
    REFERENCES mod_versions(mod_id, version) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_mod_cap_approval_lookup
  ON mod_capability_approval(mod_id, version, capability, approved);
CREATE INDEX idx_user_mod_grant_lookup
  ON user_mod_capability_grant(user_id, mod_id, version, capability, granted);

CREATE TABLE mod_capability_approval_audit (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  mod_id VARCHAR(100) NOT NULL,
  version VARCHAR(64) NOT NULL,
  manifest_sha256 CHAR(64) NOT NULL,
  publisher_id VARCHAR(100) NOT NULL,
  capability VARCHAR(80) NOT NULL,
  approved BOOLEAN NOT NULL,
  decision_reason VARCHAR(500) NOT NULL DEFAULT '',
  decided_by VARCHAR(100) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_cap_approval_audit_mod_time(mod_id, version, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE user_mod_capability_grant_audit (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  mod_id VARCHAR(100) NOT NULL,
  version VARCHAR(64) NOT NULL,
  manifest_sha256 CHAR(64) NOT NULL,
  capability VARCHAR(80) NOT NULL,
  granted BOOLEAN NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_user_cap_grant_audit(user_id, mod_id, created_at),
  CONSTRAINT fk_user_cap_grant_audit_user FOREIGN KEY (user_id)
    REFERENCES community_user(user_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
