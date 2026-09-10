CREATE TABLE task_settings (
  user_id VARCHAR(36) PRIMARY KEY,
  quiet_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  quiet_start_time TIME NOT NULL DEFAULT '22:30:00',
  quiet_end_time TIME NOT NULL DEFAULT '07:00:00',
  version INT NOT NULL DEFAULT 0,
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_task_setting_user FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT ck_task_setting_version CHECK (version >= 0)
);

CREATE TABLE task_notification_events (
  id VARCHAR(36) PRIMARY KEY,
  user_id VARCHAR(36) NOT NULL,
  task_instance_id VARCHAR(36),
  device_key_hash VARCHAR(128) NOT NULL,
  event_type VARCHAR(16) NOT NULL,
  scheduled_for TIMESTAMP(6),
  occurred_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  idempotency_key VARCHAR(100) NOT NULL,
  CONSTRAINT fk_task_event_user FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT fk_task_event_instance FOREIGN KEY (task_instance_id) REFERENCES task_instances(id),
  CONSTRAINT uk_task_event_key UNIQUE (user_id, idempotency_key),
  CONSTRAINT ck_task_event_type CHECK (event_type IN ('SCHEDULED','CANCELLED','OPENED'))
);

CREATE TABLE task_operation_keys (
  user_id VARCHAR(36) NOT NULL,
  idempotency_key VARCHAR(100) NOT NULL,
  instance_id VARCHAR(36) NOT NULL,
  operation_type VARCHAR(16) NOT NULL,
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (user_id, idempotency_key),
  CONSTRAINT fk_task_operation_user FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT fk_task_operation_instance FOREIGN KEY (instance_id) REFERENCES task_instances(id)
);

CREATE INDEX idx_task_event_audit ON task_notification_events(user_id, task_instance_id, occurred_at);
