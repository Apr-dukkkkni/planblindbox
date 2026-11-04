CREATE TABLE community_user (
  user_id BIGINT PRIMARY KEY AUTO_INCREMENT,
  username VARCHAR(50) NOT NULL,
  email VARCHAR(100) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  gender VARCHAR(16) NOT NULL,
  avatar VARCHAR(500) NULL,
  birthday DATE NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
  credential_version BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  last_login_at TIMESTAMP NULL,
  CONSTRAINT uk_community_email UNIQUE (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE password_reset_challenge (
  challenge_id CHAR(36) PRIMARY KEY,
  user_id BIGINT NOT NULL,
  code_mac CHAR(64) NOT NULL,
  attempts INT NOT NULL DEFAULT 0,
  expires_at TIMESTAMP NOT NULL,
  consumed_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_reset_user (user_id),
  FOREIGN KEY(user_id) REFERENCES community_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE password_reset_rate (
  rate_key CHAR(64) NOT NULL,
  bucket_start BIGINT NOT NULL,
  hits INT NOT NULL DEFAULT 0,
  PRIMARY KEY(rate_key,bucket_start)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE password_reset_budget (
  user_id BIGINT PRIMARY KEY,
  attempts INT NOT NULL DEFAULT 0,
  window_start TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(user_id) REFERENCES community_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE password_reset_cooldown (
  rate_key CHAR(64) PRIMARY KEY,
  next_allowed_at TIMESTAMP NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
