CREATE TABLE hydration_settings (
  user_id VARCHAR(36) PRIMARY KEY,
  daily_target_ml INT,
  default_cup_ml INT NOT NULL DEFAULT 250,
  reminder_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  reminder_start_time TIME NOT NULL DEFAULT '08:00:00',
  reminder_end_time TIME NOT NULL DEFAULT '22:00:00',
  reminder_interval_minutes INT NOT NULL DEFAULT 120,
  quiet_start_time TIME,
  quiet_end_time TIME,
  target_source VARCHAR(16) NOT NULL DEFAULT 'DEFAULT',
  source_plan_version INT,
  version INT NOT NULL DEFAULT 1,
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_hydration_settings_user FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT ck_hydration_target CHECK (
    daily_target_ml IS NULL OR (daily_target_ml BETWEEN 500 AND 6000 AND MOD(daily_target_ml, 50) = 0)),
  CONSTRAINT ck_hydration_cup CHECK (default_cup_ml BETWEEN 50 AND 2000),
  CONSTRAINT ck_hydration_interval CHECK (reminder_interval_minutes BETWEEN 15 AND 720),
  CONSTRAINT ck_hydration_target_source CHECK (
    target_source = 'USER' OR target_source = 'PLAN' OR target_source = 'DEFAULT'),
  CONSTRAINT ck_hydration_settings_version CHECK (version >= 1),
  CONSTRAINT ck_hydration_quiet_times CHECK (
    (quiet_start_time IS NULL AND quiet_end_time IS NULL)
    OR (quiet_start_time IS NOT NULL AND quiet_end_time IS NOT NULL))
);

CREATE TABLE hydration_entries (
  id VARCHAR(36) PRIMARY KEY,
  user_id VARCHAR(36) NOT NULL,
  amount_ml INT NOT NULL,
  occurred_at TIMESTAMP(6) NOT NULL,
  timezone VARCHAR(64) NOT NULL,
  source VARCHAR(16) NOT NULL,
  idempotency_key VARCHAR(100) NOT NULL,
  deleted_at TIMESTAMP(6),
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_hydration_entry_user FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT uk_hydration_entry_idempotency UNIQUE (user_id, idempotency_key),
  CONSTRAINT ck_hydration_amount CHECK (amount_ml BETWEEN 1 AND 3000),
  CONSTRAINT ck_hydration_source CHECK (
    source = 'QUICK' OR source = 'PRESET' OR source = 'CUSTOM')
);

CREATE INDEX idx_hydration_entry_user_time
  ON hydration_entries(user_id, occurred_at);
CREATE INDEX idx_hydration_entry_active_time
  ON hydration_entries(user_id, deleted_at, occurred_at);
