-- PlanBlindBox Step5: 每日习惯打卡奖励配置。
-- 需在 plan_blind_box 数据库执行一次，数值仅为样例，可自行调整。
-- 不新增表，不修改旧表；若已有同名规则，不覆盖用户当前配置。
USE plan_blind_box;

INSERT INTO reward_config (type, coin, exp, water, enabled)
VALUES ('HABIT_CHECK_IN', 2, 5, 1, TRUE)
ON DUPLICATE KEY UPDATE type = type;

SELECT reward_config_id, type, coin, exp, water, enabled
FROM reward_config WHERE type = 'HABIT_CHECK_IN';
