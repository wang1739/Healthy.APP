CREATE TABLE sleep_records (
  id VARCHAR(36) PRIMARY KEY,
  user_id VARCHAR(36) NOT NULL,
  record_type VARCHAR(8) NOT NULL,
  started_at TIMESTAMP(6) NOT NULL,
  ended_at TIMESTAMP(6) NOT NULL,
  timezone VARCHAR(64) NOT NULL,
  wake_local_date DATE NOT NULL,
  active_night_wake_date DATE,
  duration_minutes INT NOT NULL,
  quality_score INT,
  note VARCHAR(500),
  source VARCHAR(16) NOT NULL DEFAULT 'MANUAL',
  external_source_id VARCHAR(100),
  idempotency_key VARCHAR(100) NOT NULL,
  deleted_at TIMESTAMP(6),
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_sleep_record_user FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT uk_sleep_record_idempotency UNIQUE (user_id, idempotency_key),
  CONSTRAINT uk_sleep_active_night UNIQUE (user_id, active_night_wake_date),
  CONSTRAINT ck_sleep_record_type CHECK (record_type IN ('NIGHT','NAP')),
  CONSTRAINT ck_sleep_record_times CHECK (ended_at > started_at),
  CONSTRAINT ck_sleep_record_duration CHECK (
    (record_type='NIGHT' AND duration_minutes BETWEEN 30 AND 960) OR
    (record_type='NAP' AND duration_minutes BETWEEN 5 AND 240)),
  CONSTRAINT ck_sleep_record_quality CHECK (quality_score IS NULL OR quality_score BETWEEN 1 AND 5),
  CONSTRAINT ck_sleep_record_note CHECK (note IS NULL OR CHAR_LENGTH(note) <= 500),
  CONSTRAINT ck_sleep_record_source CHECK (source='MANUAL'),
  CONSTRAINT ck_sleep_active_night CHECK (
    (record_type='NIGHT' AND deleted_at IS NULL AND active_night_wake_date=wake_local_date) OR
    ((record_type<>'NIGHT' OR deleted_at IS NOT NULL) AND active_night_wake_date IS NULL))
);

CREATE TABLE sleep_record_tags (
  sleep_record_id VARCHAR(36) NOT NULL,
  tag_code VARCHAR(24) NOT NULL,
  PRIMARY KEY (sleep_record_id, tag_code),
  CONSTRAINT fk_sleep_tag_record FOREIGN KEY (sleep_record_id) REFERENCES sleep_records(id),
  CONSTRAINT ck_sleep_tag_code CHECK (tag_code IN
    ('STRESS','CAFFEINE','ALCOHOL','SCREEN_TIME','NIGHT_AWAKENING','NOISE','DISCOMFORT'))
);

CREATE INDEX idx_sleep_user_wake_date ON sleep_records(user_id, wake_local_date, record_type);
CREATE INDEX idx_sleep_user_interval ON sleep_records(user_id, started_at, ended_at);
CREATE INDEX idx_sleep_user_active_wake ON sleep_records(user_id, deleted_at, wake_local_date);
