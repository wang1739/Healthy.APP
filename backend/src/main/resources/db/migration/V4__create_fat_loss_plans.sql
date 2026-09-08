ALTER TABLE health_profiles ADD COLUMN metabolic_basis VARCHAR(16);

UPDATE health_profiles
SET metabolic_basis = sex
WHERE sex IN ('MALE', 'FEMALE');

CREATE TABLE health_plans (
  id VARCHAR(36) PRIMARY KEY,
  user_id VARCHAR(36) NOT NULL UNIQUE,
  status VARCHAR(16) NOT NULL,
  phase_start_date DATE NOT NULL,
  phase_end_date DATE NOT NULL,
  current_version INT NOT NULL,
  paused_at TIMESTAMP(6),
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_plan_user FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE health_plan_versions (
  id VARCHAR(36) PRIMARY KEY,
  plan_id VARCHAR(36) NOT NULL,
  version_number INT NOT NULL,
  rule_version VARCHAR(32) NOT NULL,
  profile_version INT NOT NULL,
  calculation_date DATE NOT NULL,
  age INT NOT NULL,
  metabolic_basis VARCHAR(16) NOT NULL,
  height_cm DECIMAL(5,2) NOT NULL,
  weight_kg DECIMAL(5,2) NOT NULL,
  activity_level VARCHAR(24) NOT NULL,
  target_weight_kg DECIMAL(5,2) NOT NULL,
  requested_target_date DATE NOT NULL,
  bmi DECIMAL(5,1) NOT NULL,
  bmr_kcal INT NOT NULL,
  tdee_kcal INT NOT NULL,
  target_kcal INT NOT NULL,
  protein_g INT NOT NULL,
  carbs_g INT NOT NULL,
  fat_g INT NOT NULL,
  water_ml INT NOT NULL,
  exercise_days INT NOT NULL,
  exercise_minutes INT NOT NULL,
  sleep_hours DECIMAL(3,1) NOT NULL,
  expected_weekly_change_kg DECIMAL(4,2) NOT NULL,
  suggested_target_date DATE NOT NULL,
  safety_message VARCHAR(255) NOT NULL,
  adjustment_reason VARCHAR(200),
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_plan_version_plan FOREIGN KEY (plan_id) REFERENCES health_plans(id),
  CONSTRAINT uk_plan_version UNIQUE (plan_id, version_number)
);

CREATE INDEX idx_plan_version_history ON health_plan_versions(plan_id, version_number);
