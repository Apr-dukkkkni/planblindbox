-- 水滴仅由服务器发放。本迁移只新增可信账本，不导入客户端历史余额。
CREATE TABLE user_water_wallet (
  user_id BIGINT NOT NULL PRIMARY KEY,
  balance BIGINT NOT NULL DEFAULT 0,
  current_streak INT NOT NULL DEFAULT 0,
  longest_streak INT NOT NULL DEFAULT 0,
  total_check_in_days INT NOT NULL DEFAULT 0,
  last_sign_in_date DATE NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_water_wallet_user FOREIGN KEY(user_id) REFERENCES community_user(user_id),
  CONSTRAINT chk_wallet_balance CHECK (balance >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE user_water_checkin (
  checkin_id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  business_date DATE NOT NULL,
  streak_day INT NOT NULL,
  water_awarded INT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_water_checkin_user FOREIGN KEY(user_id) REFERENCES community_user(user_id),
  CONSTRAINT uk_water_user_date UNIQUE (user_id, business_date),
  INDEX idx_water_user_date (user_id, business_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE user_water_ledger (
  ledger_id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  change_amount BIGINT NOT NULL,
  balance_after BIGINT NOT NULL,
  source_type VARCHAR(40) NOT NULL,
  source_id BIGINT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_water_ledger_user FOREIGN KEY(user_id) REFERENCES community_user(user_id),
  CONSTRAINT uk_water_ledger_source UNIQUE(user_id,source_type,source_id),
  INDEX idx_water_ledger_user_time(user_id,created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
