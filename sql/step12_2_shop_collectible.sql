-- Step 12.2：让开盒记录保留实际抽中的收藏品 ID。
-- 前置条件：shop_reward.item_id 已存在，且 collectible_item 已创建。
-- 本迁移只执行一次。请先备份数据库。

ALTER TABLE shop_open_record
    ADD COLUMN collectible_item_id BIGINT NULL AFTER reward_id,
    ADD KEY idx_shop_open_collectible_item (collectible_item_id),
    ADD CONSTRAINT fk_shop_open_collectible_item
        FOREIGN KEY (collectible_item_id)
        REFERENCES collectible_item(item_id);

-- 验证：原有数值奖励的 collectible_item_id 应全部为 NULL。
SELECT open_id, reward_id, reward_type, collectible_item_id
FROM shop_open_record
ORDER BY open_id DESC
LIMIT 20;
