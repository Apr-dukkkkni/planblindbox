-- V2.3：MySQL 是下载事件事实来源；Outbox 保证下载事务与消息意图原子提交。
CREATE TABLE mod_download_outbox (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  download_event_id BIGINT NOT NULL,
  mod_id VARCHAR(100) NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  published_at TIMESTAMP NULL,
  CONSTRAINT uk_outbox_download_event UNIQUE (download_event_id),
  CONSTRAINT fk_outbox_download_event FOREIGN KEY (download_event_id)
    REFERENCES mod_download_events(id)
);
CREATE INDEX idx_mod_outbox_status ON mod_download_outbox(status, id);
