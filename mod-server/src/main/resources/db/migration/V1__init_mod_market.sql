CREATE TABLE mod_packages (
  mod_id VARCHAR(100) PRIMARY KEY,
  name VARCHAR(60) NOT NULL,
  description VARCHAR(300) NOT NULL,
  latest_version VARCHAR(32) NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE mod_versions (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  mod_id VARCHAR(100) NOT NULL,
  version VARCHAR(32) NOT NULL,
  manifest_json TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_mod_versions_mod FOREIGN KEY (mod_id) REFERENCES mod_packages(mod_id),
  CONSTRAINT uk_mod_version UNIQUE (mod_id, version)
);
CREATE TABLE mod_download_events (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  request_id VARCHAR(36) NOT NULL,
  mod_id VARCHAR(100) NOT NULL,
  version VARCHAR(32) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT uk_download_request UNIQUE (request_id),
  CONSTRAINT fk_download_version FOREIGN KEY (mod_id, version) REFERENCES mod_versions(mod_id, version)
);
CREATE INDEX idx_mod_enabled_name ON mod_packages(enabled, name);
CREATE INDEX idx_download_mod_time ON mod_download_events(mod_id, created_at);
