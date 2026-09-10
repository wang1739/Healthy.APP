CREATE TABLE task_templates (
  id VARCHAR(36) PRIMARY KEY,
  user_id VARCHAR(36) NOT NULL,
  source VARCHAR(8) NOT NULL,
  plan_id VARCHAR(36),
  plan_version INT,
  task_code VARCHAR(40),
  title VARCHAR(80) NOT NULL,
  note VARCHAR(500),
  category VARCHAR(12) NOT NULL,
  priority VARCHAR(12) NOT NULL,
  all_day BOOLEAN NOT NULL,
  local_time TIME,
  recurrence_type VARCHAR(16) NOT NULL,
  weekdays_mask INT,
  reminder_offset_minutes INT,
  health_link_type VARCHAR(32),
  health_link_target INT,
  effective_from DATE NOT NULL,
  disabled_from DATE,
  user_overridden BOOLEAN NOT NULL DEFAULT FALSE,
  version INT NOT NULL DEFAULT 0,
  idempotency_key VARCHAR(100),
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_task_template_user FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT fk_task_template_plan FOREIGN KEY (plan_id) REFERENCES health_plans(id),
  CONSTRAINT uk_task_template_create UNIQUE (user_id, idempotency_key),
  CONSTRAINT uk_task_template_plan_code UNIQUE (user_id, plan_id, plan_version, task_code),
  CONSTRAINT ck_task_template_source CHECK (source IN ('PLAN','USER')),
  CONSTRAINT ck_task_template_plan CHECK (
    (source='PLAN' AND plan_id IS NOT NULL AND plan_version IS NOT NULL AND task_code IS NOT NULL) OR
    (source='USER' AND plan_id IS NULL AND plan_version IS NULL AND task_code IS NULL)),
  CONSTRAINT ck_task_template_title CHECK (CHAR_LENGTH(TRIM(title)) BETWEEN 1 AND 80),
  CONSTRAINT ck_task_template_note CHECK (note IS NULL OR CHAR_LENGTH(note) <= 500),
  CONSTRAINT ck_task_template_category CHECK (category IN ('HEALTH','WORK','LIFE','STUDY','OTHER')),
  CONSTRAINT ck_task_template_priority CHECK (priority IN ('NORMAL','IMPORTANT','URGENT')),
  CONSTRAINT ck_task_template_time CHECK ((all_day=TRUE AND local_time IS NULL) OR (all_day=FALSE AND local_time IS NOT NULL)),
  CONSTRAINT ck_task_template_recurrence CHECK (recurrence_type IN ('NONE','DAILY','WEEKDAYS','WEEKENDS','WEEKLY_DAYS')),
  CONSTRAINT ck_task_template_weekdays CHECK (
    (recurrence_type='WEEKLY_DAYS' AND weekdays_mask BETWEEN 1 AND 127) OR
    (recurrence_type<>'WEEKLY_DAYS' AND weekdays_mask IS NULL)),
  CONSTRAINT ck_task_template_reminder CHECK (reminder_offset_minutes IS NULL OR reminder_offset_minutes IN (0,5,15,30,60)),
  CONSTRAINT ck_task_template_reminder_time CHECK (reminder_offset_minutes IS NULL OR all_day=FALSE),
  CONSTRAINT ck_task_template_dates CHECK (disabled_from IS NULL OR disabled_from >= effective_from),
  CONSTRAINT ck_task_template_version CHECK (version >= 0)
);

CREATE TABLE task_instances (
  id VARCHAR(36) PRIMARY KEY,
  user_id VARCHAR(36) NOT NULL,
  template_id VARCHAR(36) NOT NULL,
  original_local_date DATE NOT NULL,
  current_local_date DATE NOT NULL,
  original_due_at TIMESTAMP(6),
  current_due_at TIMESTAMP(6),
  timezone VARCHAR(64) NOT NULL,
  status VARCHAR(12) NOT NULL,
  completion_source VARCHAR(20),
  completed_at TIMESTAMP(6),
  skipped_at TIMESTAMP(6),
  skip_reason VARCHAR(200),
  postponed_from TIMESTAMP(6),
  postpone_count INT NOT NULL DEFAULT 0,
  title VARCHAR(80) NOT NULL,
  note VARCHAR(500),
  category VARCHAR(12) NOT NULL,
  priority VARCHAR(12) NOT NULL,
  all_day BOOLEAN NOT NULL,
  local_time TIME,
  reminder_offset_minutes INT,
  deleted_at TIMESTAMP(6),
  version INT NOT NULL DEFAULT 0,
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_task_instance_user FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT fk_task_instance_template FOREIGN KEY (template_id) REFERENCES task_templates(id),
  CONSTRAINT uk_task_instance_template_date UNIQUE (template_id, original_local_date),
  CONSTRAINT ck_task_instance_status CHECK (status IN ('PENDING','COMPLETED','SKIPPED')),
  CONSTRAINT ck_task_instance_completion CHECK (completion_source IS NULL OR completion_source IN ('USER','AUTO_HEALTH_DATA')),
  CONSTRAINT ck_task_instance_state CHECK (
    (status='PENDING' AND completion_source IS NULL AND completed_at IS NULL AND skipped_at IS NULL) OR
    (status='COMPLETED' AND completion_source IS NOT NULL AND completed_at IS NOT NULL AND skipped_at IS NULL) OR
    (status='SKIPPED' AND completion_source IS NULL AND completed_at IS NULL AND skipped_at IS NOT NULL)),
  CONSTRAINT ck_task_instance_title CHECK (CHAR_LENGTH(TRIM(title)) BETWEEN 1 AND 80),
  CONSTRAINT ck_task_instance_note CHECK (note IS NULL OR CHAR_LENGTH(note) <= 500),
  CONSTRAINT ck_task_instance_category CHECK (category IN ('HEALTH','WORK','LIFE','STUDY','OTHER')),
  CONSTRAINT ck_task_instance_priority CHECK (priority IN ('NORMAL','IMPORTANT','URGENT')),
  CONSTRAINT ck_task_instance_time CHECK (
    (all_day=TRUE AND local_time IS NULL AND original_due_at IS NULL AND current_due_at IS NULL) OR
    (all_day=FALSE AND local_time IS NOT NULL AND original_due_at IS NOT NULL AND current_due_at IS NOT NULL)),
  CONSTRAINT ck_task_instance_reminder CHECK (reminder_offset_minutes IS NULL OR reminder_offset_minutes IN (0,5,15,30,60)),
  CONSTRAINT ck_task_instance_postpone CHECK (postpone_count >= 0),
  CONSTRAINT ck_task_instance_version CHECK (version >= 0)
);

CREATE INDEX idx_task_template_user_dates ON task_templates(user_id, effective_from, disabled_from);
CREATE INDEX idx_task_template_plan ON task_templates(user_id, plan_id, plan_version);
CREATE INDEX idx_task_instance_user_date ON task_instances(user_id, current_local_date, deleted_at);
CREATE INDEX idx_task_instance_user_due ON task_instances(user_id, status, current_due_at);
CREATE INDEX idx_task_instance_original_date ON task_instances(user_id, original_local_date, deleted_at);
