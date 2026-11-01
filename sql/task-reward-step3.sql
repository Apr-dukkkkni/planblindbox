-- PlanBlindBox Step3 - 奖励配置（示例数值，按需更改）
-- 只需要执行一次，不需要改表，不会删除任何已有数据。
-- type 在 reward_config 中具有 UNIQUE 约束。
-- 如果已存在 TASK_COMPLETE，运行前先确认下面示例数值是否符合预期。
INSERT INTO reward_config (type, coin, exp, water, enabled)
VALUES ('TASK_COMPLETE', 10, 20, 2, TRUE)
ON DUPLICATE KEY UPDATE type = type;

-- 查看配置是否存在、是否启用
SELECT reward_config_id, type, coin, exp, water, enabled
FROM reward_config WHERE type='TASK_COMPLETE';
