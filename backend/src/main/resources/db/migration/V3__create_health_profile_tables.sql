CREATE TABLE health_profiles (
  user_id VARCHAR(36) PRIMARY KEY,
  birth_date DATE,
  sex VARCHAR(20),
  height_cm DECIMAL(5,2),
  activity_level VARCHAR(24),
  work_style VARCHAR(24),
  sleep_hours DECIMAL(4,2),
  exercise_days INT,
  current_step INT NOT NULL DEFAULT 0,
  completed BOOLEAN NOT NULL DEFAULT FALSE,
  risk_blocked BOOLEAN NOT NULL DEFAULT FALSE,
  plan_needs_recalculation BOOLEAN NOT NULL DEFAULT FALSE,
  version INT NOT NULL DEFAULT 1,
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_profile_user FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE body_measurements (
  id VARCHAR(36) PRIMARY KEY,
  user_id VARCHAR(36) NOT NULL,
  weight_kg DECIMAL(5,2) NOT NULL,
  waist_cm DECIMAL(5,2),
  body_fat_percent DECIMAL(5,2),
  measured_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_measurement_user FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_measurement_user_time ON body_measurements(user_id, measured_at);

CREATE TABLE health_goals (
  user_id VARCHAR(36) PRIMARY KEY,
  goal_type VARCHAR(24) NOT NULL,
  target_weight_kg DECIMAL(5,2),
  target_date DATE,
  updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_goal_user FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE dietary_preferences (
  user_id VARCHAR(36) PRIMARY KEY,
  diet_type VARCHAR(24) NOT NULL,
  allergies VARCHAR(500),
  avoid_foods VARCHAR(500),
  updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_preference_user FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE health_risk_answers (
  id VARCHAR(36) PRIMARY KEY,
  user_id VARCHAR(36) NOT NULL,
  pregnant BOOLEAN NOT NULL DEFAULT FALSE,
  breastfeeding BOOLEAN NOT NULL DEFAULT FALSE,
  eating_disorder_risk BOOLEAN NOT NULL DEFAULT FALSE,
  serious_chronic_disease BOOLEAN NOT NULL DEFAULT FALSE,
  unsafe_target BOOLEAN NOT NULL DEFAULT FALSE,
  risk_blocked BOOLEAN NOT NULL,
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_risk_user FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE health_permissions (
  user_id VARCHAR(36) PRIMARY KEY,
  health_data_authorized BOOLEAN NOT NULL DEFAULT FALSE,
  authorization_version VARCHAR(32),
  updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_permission_user FOREIGN KEY (user_id) REFERENCES users(id)
);
