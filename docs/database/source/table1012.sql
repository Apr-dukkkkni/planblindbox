CREATE TABLE app_user (
                          user_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '用户ID',

                          username VARCHAR(50) NOT NULL COMMENT '用户名',
                          phone VARCHAR(20) DEFAULT NULL COMMENT '手机号',
                          email VARCHAR(100) NOT NULL COMMENT '邮箱',
                          password VARCHAR(255) NOT NULL COMMENT '密码',
                          avatar VARCHAR(500) DEFAULT NULL COMMENT '头像地址',

                          status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE' COMMENT '用户状态',

                          birthday DATE DEFAULT NULL COMMENT '生日',

                          user_setting JSON DEFAULT NULL COMMENT '用户个性化设置',

                          create_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',

                          update_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                              ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',

                          last_login_time DATETIME DEFAULT NULL COMMENT '最后登录时间',

                          PRIMARY KEY (user_id),

                          UNIQUE KEY uk_user_phone (phone),
                          UNIQUE KEY uk_user_email (email)

) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci
  COMMENT = '用户表';



CREATE TABLE user_asset (
                            asset_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '资产ID',

                            user_id BIGINT NOT NULL COMMENT '用户ID',

                            coin INT NOT NULL DEFAULT 0 COMMENT '金币数量',

                            exp BIGINT NOT NULL DEFAULT 0 COMMENT '当前累计经验值',

                            water INT NOT NULL DEFAULT 0 COMMENT '水滴数量',

                            update_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                                ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',

                            PRIMARY KEY (asset_id),

                            UNIQUE KEY uk_user_asset_user_id (user_id),

                            CONSTRAINT fk_user_asset_user
                                FOREIGN KEY (user_id)
                                    REFERENCES app_user(user_id)

) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci
  COMMENT = '用户当前资产表';


CREATE TABLE level_config (
                              level INT NOT NULL COMMENT '等级',

                              required_exp BIGINT NOT NULL COMMENT '达到该等级所需累计经验',

                              badge_name VARCHAR(100) DEFAULT NULL COMMENT '等级徽章名称',

                              reward_coin INT NOT NULL DEFAULT 0 COMMENT '升级奖励金币',

                              reward_water INT NOT NULL DEFAULT 0 COMMENT '升级奖励水滴',

                              PRIMARY KEY (level)

) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci
  COMMENT = '等级配置表';


等级暂定-后边打算改成数字

INSERT INTO level_config
(level, required_exp, badge_name, reward_coin, reward_water)
VALUES
(1, 0,    '初来乍到', 0,   0),
(2, 100,  '开始行动', 20,  5),
(3, 300,  '渐入佳境', 30,  8),
(4, 600,  '坚持不懈', 50, 10),
(5, 1000, '稳步成长', 80, 15);


CREATE TABLE task (
                      task_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '任务ID',

                      user_id BIGINT NOT NULL COMMENT '所属用户ID',

                      title VARCHAR(100) NOT NULL COMMENT '任务标题',

                      note TEXT DEFAULT NULL COMMENT '任务备注',

                      start_time DATETIME DEFAULT NULL COMMENT '任务开始时间',

                      end_time DATETIME DEFAULT NULL COMMENT '任务截止时间',

                      target_count INT NOT NULL DEFAULT 1 COMMENT '目标完成次数/数量',

                      status VARCHAR(20) NOT NULL DEFAULT 'PENDING' COMMENT '任务状态',

                      importance TINYINT DEFAULT NULL COMMENT '重要程度 1-5',

                      urgency TINYINT DEFAULT NULL COMMENT '紧急程度 1-5',

                      difficulty TINYINT DEFAULT NULL COMMENT '难度 1-5',

                      priority_score DECIMAL(6,2) DEFAULT NULL COMMENT '任务优先级分数',

                      estimated_minutes INT DEFAULT NULL COMMENT '预计耗时，单位分钟',

                      create_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                          COMMENT '创建时间',

                      update_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                          ON UPDATE CURRENT_TIMESTAMP
        COMMENT '更新时间',

                      PRIMARY KEY (task_id),

                      INDEX idx_task_user_id (user_id),

                      INDEX idx_task_user_status (user_id, status),

                      INDEX idx_task_user_start_time (user_id, start_time),

                      INDEX idx_task_user_end_time (user_id, end_time),

                      CONSTRAINT fk_task_user
                          FOREIGN KEY (user_id)
                              REFERENCES app_user(user_id)

) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci
  COMMENT = '任务定义表';


CREATE TABLE task_record (
                             task_record_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '任务执行记录ID',

                             task_id BIGINT NOT NULL COMMENT '关联任务ID',

                             record_date DATE NOT NULL COMMENT '执行日期',

                             status VARCHAR(20) NOT NULL DEFAULT 'IN_PROGRESS'
                                 COMMENT '本次执行状态',

                             finish_time DATETIME DEFAULT NULL COMMENT '本次完成时间',

                             actual_count INT NOT NULL DEFAULT 0 COMMENT '当天实际完成数量',

                             create_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                                 COMMENT '记录创建时间',

                             update_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                                 ON UPDATE CURRENT_TIMESTAMP
        COMMENT '记录更新时间',

                             PRIMARY KEY (task_record_id),

                             UNIQUE KEY uk_task_record_date (task_id, record_date),

                             INDEX idx_task_record_date (record_date),

                             CONSTRAINT fk_task_record_task
                                 FOREIGN KEY (task_id)
                                     REFERENCES task(task_id)

) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci
  COMMENT = '任务执行记录表';



CREATE TABLE habit (
                       habit_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '习惯ID',

                       user_id BIGINT NOT NULL COMMENT '所属用户ID',

                       name VARCHAR(100) NOT NULL COMMENT '习惯名称',

                       note TEXT DEFAULT NULL COMMENT '习惯备注',

                       start_date DATE NOT NULL COMMENT '习惯开始日期',

                       end_date DATE DEFAULT NULL COMMENT '习惯结束日期，为空表示长期执行',

                       repeat_rule JSON NOT NULL COMMENT '周期规则',

                       status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
                           COMMENT '习惯状态',

                       create_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                           COMMENT '创建时间',

                       update_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                           ON UPDATE CURRENT_TIMESTAMP
        COMMENT '更新时间',

                       PRIMARY KEY (habit_id),

                       INDEX idx_habit_user_id (user_id),

                       INDEX idx_habit_user_status (user_id, status),

                       INDEX idx_habit_user_start_date (user_id, start_date),

                       CONSTRAINT fk_habit_user
                           FOREIGN KEY (user_id)
                               REFERENCES app_user(user_id)

) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci
  COMMENT = '习惯定义表';



CREATE TABLE habit_record (
                              habit_record_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '习惯执行记录ID',

                              habit_id BIGINT NOT NULL COMMENT '关联习惯ID',

                              record_date DATE NOT NULL COMMENT '执行日期',

                              status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
                                  COMMENT '当日执行状态',

                              finish_time DATETIME DEFAULT NULL COMMENT '完成时间',

                              actual_count INT NOT NULL DEFAULT 0 COMMENT '当日实际完成次数',

                              create_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                                  COMMENT '创建时间',

                              update_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                                  ON UPDATE CURRENT_TIMESTAMP
        COMMENT '更新时间',

                              PRIMARY KEY (habit_record_id),

                              UNIQUE KEY uk_habit_record_date (habit_id, record_date),

                              INDEX idx_habit_record_date (record_date),

                              CONSTRAINT fk_habit_record_habit
                                  FOREIGN KEY (habit_id)
                                      REFERENCES habit(habit_id)

) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci
  COMMENT = '习惯执行记录表';


CREATE TABLE reminder_setting (
                                  setting_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '提醒设置ID',

                                  user_id BIGINT NOT NULL COMMENT '所属用户ID',

                                  target_type VARCHAR(20) NOT NULL COMMENT '提醒目标类型：TASK / HABIT',

                                  target_id BIGINT NOT NULL COMMENT '目标ID，对应task_id或habit_id',

                                  remind_time DATETIME NOT NULL COMMENT '提醒时间',

                                  enabled BOOLEAN NOT NULL DEFAULT TRUE COMMENT '是否启用提醒',

                                  create_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                                      COMMENT '创建时间',

                                  update_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                                      ON UPDATE CURRENT_TIMESTAMP
        COMMENT '更新时间',

                                  PRIMARY KEY (setting_id),

                                  INDEX idx_reminder_user_id (user_id),

                                  INDEX idx_reminder_target (target_type, target_id),

                                  INDEX idx_reminder_time (remind_time),

                                  CONSTRAINT fk_reminder_user
                                      FOREIGN KEY (user_id)
                                          REFERENCES app_user(user_id)

) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci
  COMMENT = '统一提醒设置表';


CREATE TABLE reward_config (
                               reward_config_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '奖励配置ID',

                               type VARCHAR(50) NOT NULL COMMENT '奖励行为类型',

                               coin INT NOT NULL DEFAULT 0 COMMENT '奖励金币',

                               exp BIGINT NOT NULL DEFAULT 0 COMMENT '奖励经验',

                               water INT NOT NULL DEFAULT 0 COMMENT '奖励水滴',

                               enabled BOOLEAN NOT NULL DEFAULT TRUE COMMENT '奖励规则是否启用',

                               create_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                                   COMMENT '创建时间',

                               update_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                                   ON UPDATE CURRENT_TIMESTAMP
        COMMENT '更新时间',

                               PRIMARY KEY (reward_config_id),

                               UNIQUE KEY uk_reward_config_type (type)

) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci
  COMMENT = '奖励规则配置表';


CREATE TABLE asset_record (
                              record_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '资产流水ID',

                              user_id BIGINT NOT NULL COMMENT '所属用户ID',

                              action VARCHAR(50) NOT NULL COMMENT '资产变化行为',

                              asset_type VARCHAR(20) NOT NULL COMMENT '资产类型：COIN / EXP / WATER',

                              amount BIGINT NOT NULL COMMENT '变化数量，正数增加，负数扣除',

                              source VARCHAR(50) DEFAULT NULL COMMENT '资产变化来源',

                              source_id BIGINT DEFAULT NULL COMMENT '来源业务ID',

                              create_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                                  COMMENT '创建时间',

                              PRIMARY KEY (record_id),

                              INDEX idx_asset_record_user_id (user_id),

                              INDEX idx_asset_record_user_time (user_id, create_time),

                              INDEX idx_asset_record_source (source, source_id),

                              CONSTRAINT fk_asset_record_user
                                  FOREIGN KEY (user_id)
                                      REFERENCES app_user(user_id)

) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci
  COMMENT = '用户资产流水表';



