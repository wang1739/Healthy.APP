ALTER TABLE user_devices ADD COLUMN system_name VARCHAR(40);
ALTER TABLE health_plan_versions ADD COLUMN source_measurement_id VARCHAR(36);

ALTER TABLE account_deletion_requests ADD COLUMN scheduled_for TIMESTAMP(6);
ALTER TABLE account_deletion_requests ADD COLUMN recovered_at TIMESTAMP(6);

CREATE TABLE privacy_documents (
  id VARCHAR(36) PRIMARY KEY,
  document_type VARCHAR(32) NOT NULL,
  version VARCHAR(32) NOT NULL,
  effective_at TIMESTAMP(6) NOT NULL,
  change_summary VARCHAR(500) NOT NULL,
  content_text TEXT NOT NULL,
  material_change BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT uk_privacy_document_version UNIQUE (document_type, version)
);

CREATE TABLE consent_events (
  id VARCHAR(36) PRIMARY KEY,
  user_id VARCHAR(36) NOT NULL,
  document_type VARCHAR(32) NOT NULL,
  document_version VARCHAR(32) NOT NULL,
  action VARCHAR(20) NOT NULL,
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_consent_event_user FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_consent_event_user_type
  ON consent_events(user_id, document_type, created_at);

CREATE TABLE security_events (
  id VARCHAR(36) PRIMARY KEY,
  user_id VARCHAR(36) NOT NULL,
  event_type VARCHAR(40) NOT NULL,
  device_id VARCHAR(36),
  device_name VARCHAR(100),
  result VARCHAR(20) NOT NULL,
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_security_event_user FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_security_event_user_time ON security_events(user_id, created_at);

CREATE TABLE data_export_jobs (
  id VARCHAR(36) PRIMARY KEY,
  user_id VARCHAR(36) NOT NULL,
  status VARCHAR(20) NOT NULL,
  data_cutoff_at TIMESTAMP(6) NOT NULL,
  file_path VARCHAR(500),
  expires_at TIMESTAMP(6),
  failure_code VARCHAR(40),
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  completed_at TIMESTAMP(6),
  CONSTRAINT fk_data_export_user FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_data_export_user_status ON data_export_jobs(user_id, status, created_at);
CREATE INDEX idx_data_export_expiry ON data_export_jobs(expires_at, status);

CREATE TABLE health_data_deletion_jobs (
  id VARCHAR(36) PRIMARY KEY,
  user_id VARCHAR(36) NOT NULL,
  status VARCHAR(20) NOT NULL,
  selection_json TEXT NOT NULL,
  impact_json TEXT NOT NULL,
  failure_code VARCHAR(40),
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  completed_at TIMESTAMP(6),
  CONSTRAINT fk_health_deletion_user FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_health_deletion_user_status
  ON health_data_deletion_jobs(user_id, status, created_at);

CREATE TABLE phone_change_appeals (
  id VARCHAR(36) PRIMARY KEY,
  user_id VARCHAR(36) NOT NULL,
  new_phone VARCHAR(20) NOT NULL,
  status VARCHAR(20) NOT NULL,
  material_reference VARCHAR(500),
  result_reason VARCHAR(200),
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  completed_at TIMESTAMP(6),
  material_delete_after TIMESTAMP(6),
  CONSTRAINT fk_phone_appeal_user FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_phone_appeal_user_status ON phone_change_appeals(user_id, status, created_at);

INSERT INTO privacy_documents
  (id, document_type, version, effective_at, change_summary, content_text, material_change)
VALUES
  ('privacy-policy-2026-09', 'PRIVACY_POLICY', '2026-09', CURRENT_TIMESTAMP(6),
   '首次建立隐私政策版本记录', '轻食记隐私政策', FALSE),
  ('health-auth-2026-09', 'HEALTH_DATA_AUTHORIZATION', '2026-09', CURRENT_TIMESTAMP(6),
   '首次建立健康数据授权版本记录', '轻食记健康数据授权说明', FALSE);

INSERT INTO consent_events (id, user_id, document_type, document_version, action, created_at)
SELECT CONCAT('p-', SUBSTRING(id, 1, 34)), user_id, 'PRIVACY_POLICY', privacy_version, 'ACCEPT', accepted_at
FROM consent_records;

INSERT INTO consent_events (id, user_id, document_type, document_version, action, created_at)
SELECT CONCAT('h-', SUBSTRING(user_id, 1, 34)), user_id, 'HEALTH_DATA_AUTHORIZATION', authorization_version, 'ACCEPT', updated_at
FROM health_permissions
WHERE health_data_authorized = TRUE AND authorization_version IS NOT NULL;
