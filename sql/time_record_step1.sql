-- PlanBlindBox 时间记录模块第一阶段：手动时间块记录
-- 执行一次即可；不会修改或删除现有业务数据。
CREATE TABLE IF NOT EXISTS time_record (
    time_record_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '时间记录ID',
    user_id BIGINT NOT NULL COMMENT '所属用户ID',
    task_id BIGINT DEFAULT NULL COMMENT '可选关联任务ID',
    title VARCHAR(100) NOT NULL COMMENT '时间块名称',
    category VARCHAR(50) NOT NULL DEFAULT '其他' COMMENT '时间分类',
    start_time DATETIME NOT NULL COMMENT '开始时间',
    end_time DATETIME NOT NULL COMMENT '结束时间',
    duration_minutes INT NOT NULL COMMENT '实际时长（分钟）',
    record_date DATE NOT NULL COMMENT '业务日期，凌晨05:00换日',
    note VARCHAR(500) DEFAULT NULL COMMENT '备注',
    create_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    update_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (time_record_id),
    INDEX idx_time_record_user_date_start (user_id, record_date, start_time),
    INDEX idx_time_record_task (task_id),
    CONSTRAINT fk_time_record_user FOREIGN KEY (user_id) REFERENCES app_user(user_id),
    CONSTRAINT fk_time_record_task FOREIGN KEY (task_id) REFERENCES task(task_id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='时间块记录表';



CREATE TABLE daily_sign_in (
                               sign_in_id BIGINT NOT NULL AUTO_INCREMENT,
                               user_id BIGINT NOT NULL,
                               business_date DATE NOT NULL COMMENT '按凌晨05:00切换的业务日期',
                               streak_day TINYINT UNSIGNED NOT NULL COMMENT '当月连续签到天数',
                               base_water INT UNSIGNED NOT NULL DEFAULT 5 COMMENT '每日基础水滴',
                               bonus_water INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '连续签到额外水滴',
                               total_water INT UNSIGNED NOT NULL COMMENT '当日水滴总奖励',
                               create_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

                               PRIMARY KEY (sign_in_id),
                               UNIQUE KEY uk_user_business_date (user_id, business_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;