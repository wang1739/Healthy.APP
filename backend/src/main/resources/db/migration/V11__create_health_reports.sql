CREATE TABLE health_reports (
  id VARCHAR(36) PRIMARY KEY,
  user_id VARCHAR(36) NOT NULL,
  report_type VARCHAR(12) NOT NULL,
  period_start DATE NOT NULL,
  period_end DATE NOT NULL,
  timezone VARCHAR(64) NOT NULL,
  period_status VARCHAR(16) NOT NULL,
  version INT NOT NULL,
  rules_version VARCHAR(32) NOT NULL,
  data_cutoff_at TIMESTAMP(6) NOT NULL,
  input_hash CHAR(64) NOT NULL,
  snapshot_json LONGTEXT NOT NULL,
  idempotency_key VARCHAR(100) NOT NULL,
  deleted_at TIMESTAMP(6),
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_health_report_user FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT uk_health_report_version UNIQUE (user_id, report_type, period_start, version),
  CONSTRAINT uk_health_report_idempotency UNIQUE (user_id, idempotency_key),
  CONSTRAINT ck_health_report_type CHECK (report_type IN ('DAILY','WEEKLY','MONTHLY')),
  CONSTRAINT ck_health_report_period CHECK (period_end >= period_start),
  CONSTRAINT ck_health_report_status CHECK (period_status IN ('IN_PROGRESS','COMPLETE')),
  CONSTRAINT ck_health_report_version CHECK (version > 0),
  CONSTRAINT ck_health_report_hash CHECK (CHAR_LENGTH(input_hash) = 64)
);

CREATE TABLE health_report_sources (
  report_id VARCHAR(36) NOT NULL,
  section_code VARCHAR(24) NOT NULL,
  metric_code VARCHAR(40) NOT NULL,
  source_type VARCHAR(24) NOT NULL,
  source_id VARCHAR(36) NOT NULL,
  source_local_date DATE,
  location_label VARCHAR(100) NOT NULL,
  CONSTRAINT fk_health_report_source_report FOREIGN KEY (report_id) REFERENCES health_reports(id),
  CONSTRAINT uk_health_report_source UNIQUE (report_id, section_code, metric_code, source_type, source_id),
  CONSTRAINT ck_health_report_source_section CHECK (
    section_code IN ('WEIGHT_PLAN','NUTRITION','HYDRATION','ACTIVITY','SLEEP','TASKS')),
  CONSTRAINT ck_health_report_source_type CHECK (
    source_type IN ('PLAN_VERSION','WEIGHT_MEASUREMENT','MEAL_ENTRY','HYDRATION_ENTRY',
                    'ACTIVITY_RECORD','SLEEP_RECORD','TASK_INSTANCE'))
);

CREATE INDEX idx_health_report_period
  ON health_reports(user_id, report_type, period_start, deleted_at, version);
CREATE INDEX idx_health_report_created ON health_reports(user_id, created_at);
CREATE INDEX idx_health_report_source_lookup
  ON health_report_sources(report_id, section_code, metric_code);
