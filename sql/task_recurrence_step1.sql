-- PlanBlindBox 循环计划基础结构（MySQL 8）
-- 先备份数据库再执行。此脚本只新增字段/表，不删除或重写现有任务记录。
-- 旧任务统一兼容为 ONCE；本阶段尚不开放循环任务执行入口。

SET @schema_name = DATABASE();

SET @has_recurrence_type = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = @schema_name AND TABLE_NAME = 'task'
      AND COLUMN_NAME = 'recurrence_type'
);
SET @ddl = IF(@has_recurrence_type = 0,
    'ALTER TABLE task ADD COLUMN recurrence_type VARCHAR(20) NOT NULL DEFAULT ''ONCE'' COMMENT ''任务计划类型'' AFTER target_count',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_repeat_interval_days = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = @schema_name AND TABLE_NAME = 'task'
      AND COLUMN_NAME = 'repeat_interval_days'
);
SET @ddl = IF(@has_repeat_interval_days = 0,
    'ALTER TABLE task ADD COLUMN repeat_interval_days INT NULL COMMENT ''重复执行间隔业务日数'' AFTER recurrence_type',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_repeat_days = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = @schema_name AND TABLE_NAME = 'task'
      AND COLUMN_NAME = 'repeat_days'
);
SET @ddl = IF(@has_repeat_days = 0,
    'ALTER TABLE task ADD COLUMN repeat_days VARCHAR(20) NULL COMMENT ''指定星期，ISO 1-7逗号分隔'' AFTER repeat_interval_days',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_cycle_days = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = @schema_name AND TABLE_NAME = 'task'
      AND COLUMN_NAME = 'cycle_days'
);
SET @ddl = IF(@has_cycle_days = 0,
    'ALTER TABLE task ADD COLUMN cycle_days INT NULL COMMENT ''累计周期长度业务日数'' AFTER repeat_days',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_recurrence_end_date = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = @schema_name AND TABLE_NAME = 'task'
      AND COLUMN_NAME = 'recurrence_end_date'
);
SET @ddl = IF(@has_recurrence_end_date = 0,
    'ALTER TABLE task ADD COLUMN recurrence_end_date DATE NULL COMMENT ''循环计划结束业务日期'' AFTER cycle_days',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 若之前存在同名字段但历史行中有 NULL/空值，将其归一为一次性任务。
UPDATE task SET recurrence_type = 'ONCE'
WHERE recurrence_type IS NULL OR TRIM(recurrence_type) = '';

CREATE TABLE IF NOT EXISTS task_cycle_record (
    cycle_record_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '累计周期记录ID',
    task_id BIGINT NOT NULL COMMENT '所属任务ID',
    cycle_start_date DATE NOT NULL COMMENT '周期开始业务日期',
    cycle_end_date DATE NOT NULL COMMENT '周期结束业务日期',
    target_count INT NOT NULL COMMENT '该周期目标次数快照',
    actual_count INT NOT NULL DEFAULT 0 COMMENT '该周期实际完成次数',
    status VARCHAR(20) NOT NULL DEFAULT 'IN_PROGRESS' COMMENT '周期状态',
    reward_granted TINYINT(1) NOT NULL DEFAULT 0 COMMENT '该周期奖励是否已结算',
    completed_at DATETIME NULL COMMENT '周期达标时间',
    create_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (cycle_record_id),
    UNIQUE KEY uk_task_cycle_task_start (task_id, cycle_start_date),
    KEY idx_task_cycle_task_end (task_id, cycle_end_date),
    CONSTRAINT fk_task_cycle_task
        FOREIGN KEY (task_id) REFERENCES task (task_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='任务自定义累计周期记录';
