CREATE TABLE user_progress_snapshot (
  user_id BIGINT PRIMARY KEY,
  revision BIGINT NOT NULL,
  schema_version INT NOT NULL,
  payload JSON NOT NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY(user_id) REFERENCES community_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
