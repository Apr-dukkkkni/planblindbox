-- PlanBlindBox 任务分类第一阶段迁移（MySQL 8）
-- 可重复执行：表、列、索引、外键均先检查是否存在。
-- 不会修改现有任务数据；历史任务的 category_id 保持 NULL。

CREATE TABLE IF NOT EXISTS task_category (
    category_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '任务分类ID',
    user_id BIGINT NOT NULL COMMENT '所属用户ID',
    name VARCHAR(50) NOT NULL COMMENT '分类名称',
    color VARCHAR(7) NOT NULL DEFAULT '#607D8B' COMMENT '分类颜色，#RRGGBB',
    icon VARCHAR(30) DEFAULT NULL COMMENT '可选图标标识',
    is_default TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否为系统预设分类',
    enabled TINYINT(1) NOT NULL DEFAULT 1 COMMENT '是否启用；停用不删除历史关联',
    create_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (category_id),
    UNIQUE KEY uk_task_category_user_name (user_id, name),
    KEY idx_task_category_user_enabled (user_id, enabled),
    CONSTRAINT fk_task_category_user
        FOREIGN KEY (user_id) REFERENCES app_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='用户任务分类';

SET @schema_name = DATABASE();

SET @has_category_id = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = @schema_name
      AND TABLE_NAME = 'task'
      AND COLUMN_NAME = 'category_id'
);
SET @ddl = IF(@has_category_id = 0,
    'ALTER TABLE task ADD COLUMN category_id BIGINT NULL COMMENT ''可选任务分类ID'' AFTER user_id',
    'SELECT 1');
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_task_category_index = (
    SELECT COUNT(*) FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = @schema_name
      AND TABLE_NAME = 'task'
      AND INDEX_NAME = 'idx_task_category_id'
);
SET @ddl = IF(@has_task_category_index = 0,
    'ALTER TABLE task ADD INDEX idx_task_category_id (category_id)',
    'SELECT 1');
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_task_category_fk = (
    SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
    WHERE CONSTRAINT_SCHEMA = @schema_name
      AND TABLE_NAME = 'task'
      AND CONSTRAINT_NAME = 'fk_task_category'
      AND CONSTRAINT_TYPE = 'FOREIGN KEY'
);
SET @ddl = IF(@has_task_category_fk = 0,
    'ALTER TABLE task ADD CONSTRAINT fk_task_category FOREIGN KEY (category_id) REFERENCES task_category (category_id) ON DELETE SET NULL',
    'SELECT 1');
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
