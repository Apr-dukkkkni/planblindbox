-- MySQL 8+ / InnoDB。请先备份数据库，执行后再启动商店接口。
-- 只新增商店表，不删除/修改现有 task、user_asset、asset_record。
CREATE TABLE IF NOT EXISTS shop_box (
    box_id BIGINT NOT NULL AUTO_INCREMENT,
    code VARCHAR(32) NOT NULL,
    name VARCHAR(100) NOT NULL,
    description VARCHAR(255) NOT NULL DEFAULT '',
    price_coin INT NOT NULL,
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (box_id),
    UNIQUE KEY uk_shop_box_code (code),
    CONSTRAINT chk_shop_box_price CHECK (price_coin > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS shop_reward (
    reward_id BIGINT NOT NULL AUTO_INCREMENT,
    box_id BIGINT NOT NULL,
    code VARCHAR(32) NOT NULL,
    asset_type VARCHAR(16) NOT NULL,
    amount BIGINT NOT NULL,
    weight INT NOT NULL,
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    PRIMARY KEY (reward_id),
    UNIQUE KEY uk_shop_reward_box_code (box_id, code),
    KEY idx_shop_reward_box (box_id, enabled),
    CONSTRAINT fk_shop_reward_box FOREIGN KEY (box_id) REFERENCES shop_box (box_id),
    CONSTRAINT chk_shop_reward_amount CHECK (amount > 0),
    CONSTRAINT chk_shop_reward_weight CHECK (weight > 0),
    CONSTRAINT chk_shop_reward_type CHECK (asset_type IN ('COIN','EXP','WATER'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS shop_open_record (
    open_id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    box_id BIGINT NOT NULL,
    request_id VARCHAR(36) COLLATE utf8mb4_bin NOT NULL,
    reward_id BIGINT NOT NULL,
    price_coin INT NOT NULL,
    reward_type VARCHAR(16) NOT NULL,
    reward_amount BIGINT NOT NULL,
    coin_balance_after INT NULL,
    exp_balance_after BIGINT NULL,
    water_balance_after INT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (open_id),
    UNIQUE KEY uk_shop_open_user_request (user_id, request_id),
    KEY idx_shop_open_user_time (user_id, created_at),
    CONSTRAINT fk_shop_open_box FOREIGN KEY (box_id) REFERENCES shop_box (box_id),
    CONSTRAINT fk_shop_open_reward FOREIGN KEY (reward_id) REFERENCES shop_reward (reward_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 重复执行不会覆盖运营人员后续调整的价格、权重。
INSERT INTO shop_box(code, name, description, price_coin, enabled)
VALUES ('NORMAL', '普通盲盒', '用金币兑换一次小惊喜', 50, 1),
       ('PREMIUM', '高级盲盒', '奖励更丰富的进阶盲盒', 200, 1)
ON DUPLICATE KEY UPDATE code = VALUES(code);

INSERT INTO shop_reward(box_id, code, asset_type, amount, weight, enabled)
SELECT box_id, 'COIN_15', 'COIN', 15, 50, 1 FROM shop_box WHERE code = 'NORMAL'
ON DUPLICATE KEY UPDATE code = VALUES(code);
INSERT INTO shop_reward(box_id, code, asset_type, amount, weight, enabled)
SELECT box_id, 'EXP_30', 'EXP', 30, 35, 1 FROM shop_box WHERE code = 'NORMAL'
ON DUPLICATE KEY UPDATE code = VALUES(code);
INSERT INTO shop_reward(box_id, code, asset_type, amount, weight, enabled)
SELECT box_id, 'WATER_2', 'WATER', 2, 15, 1 FROM shop_box WHERE code = 'NORMAL'
ON DUPLICATE KEY UPDATE code = VALUES(code);

INSERT INTO shop_reward(box_id, code, asset_type, amount, weight, enabled)
SELECT box_id, 'COIN_100', 'COIN', 100, 40, 1 FROM shop_box WHERE code = 'PREMIUM'
ON DUPLICATE KEY UPDATE code = VALUES(code);
INSERT INTO shop_reward(box_id, code, asset_type, amount, weight, enabled)
SELECT box_id, 'EXP_200', 'EXP', 200, 40, 1 FROM shop_box WHERE code = 'PREMIUM'
ON DUPLICATE KEY UPDATE code = VALUES(code);
INSERT INTO shop_reward(box_id, code, asset_type, amount, weight, enabled)
SELECT box_id, 'WATER_8', 'WATER', 8, 20, 1 FROM shop_box WHERE code = 'PREMIUM'
ON DUPLICATE KEY UPDATE code = VALUES(code);
