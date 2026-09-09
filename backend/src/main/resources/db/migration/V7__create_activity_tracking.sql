CREATE TABLE activity_types (
  id VARCHAR(36) PRIMARY KEY,
  owner_user_id VARCHAR(36),
  uniqueness_scope VARCHAR(36) NOT NULL,
  name VARCHAR(50) NOT NULL,
  normalized_name VARCHAR(50) NOT NULL,
  category VARCHAR(32) NOT NULL,
  low_met DECIMAL(4,2) NOT NULL,
  medium_met DECIMAL(4,2) NOT NULL,
  high_met DECIMAL(4,2) NOT NULL,
  reference_type_id VARCHAR(36),
  type_scope VARCHAR(8) NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_activity_type_owner FOREIGN KEY (owner_user_id) REFERENCES users(id),
  CONSTRAINT fk_activity_type_reference FOREIGN KEY (reference_type_id) REFERENCES activity_types(id),
  CONSTRAINT uk_activity_type_name UNIQUE (uniqueness_scope, normalized_name),
  CONSTRAINT ck_activity_type_scope CHECK (
    (type_scope='SYSTEM' AND owner_user_id IS NULL AND uniqueness_scope='SYSTEM') OR
    (type_scope='USER' AND owner_user_id IS NOT NULL AND uniqueness_scope=owner_user_id)),
  CONSTRAINT ck_activity_type_met CHECK (low_met > 0 AND medium_met > 0 AND high_met > 0)
);

CREATE TABLE activity_records (
  id VARCHAR(36) PRIMARY KEY,
  user_id VARCHAR(36) NOT NULL,
  activity_type_id VARCHAR(36) NOT NULL,
  activity_name_snapshot VARCHAR(50) NOT NULL,
  intensity VARCHAR(8) NOT NULL,
  duration_minutes INT NOT NULL,
  occurred_at TIMESTAMP(6) NOT NULL,
  timezone VARCHAR(64) NOT NULL,
  weight_kg_snapshot DECIMAL(5,2) NOT NULL,
  met_snapshot DECIMAL(4,2) NOT NULL,
  calculation_version VARCHAR(32) NOT NULL,
  estimated_kcal INT NOT NULL,
  final_kcal INT NOT NULL,
  calorie_source VARCHAR(16) NOT NULL,
  source VARCHAR(16) NOT NULL DEFAULT 'MANUAL',
  external_source_id VARCHAR(100),
  idempotency_key VARCHAR(100) NOT NULL,
  deleted_at TIMESTAMP(6),
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_activity_record_user FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT fk_activity_record_type FOREIGN KEY (activity_type_id) REFERENCES activity_types(id),
  CONSTRAINT uk_activity_record_idempotency UNIQUE (user_id, idempotency_key),
  CONSTRAINT ck_activity_record_intensity CHECK (intensity IN ('LOW','MEDIUM','HIGH')),
  CONSTRAINT ck_activity_record_duration CHECK (duration_minutes BETWEEN 1 AND 1440),
  CONSTRAINT ck_activity_record_weight CHECK (weight_kg_snapshot > 0 AND weight_kg_snapshot <= 500),
  CONSTRAINT ck_activity_record_met CHECK (met_snapshot > 0 AND met_snapshot <= 30),
  CONSTRAINT ck_activity_record_estimated CHECK (estimated_kcal BETWEEN 0 AND 10000),
  CONSTRAINT ck_activity_record_final CHECK (final_kcal BETWEEN 0 AND 10000),
  CONSTRAINT ck_activity_record_calorie_source CHECK (calorie_source IN ('ESTIMATED','USER_OVERRIDE')),
  CONSTRAINT ck_activity_record_source CHECK (source='MANUAL')
);

CREATE INDEX idx_activity_type_owner_name ON activity_types(owner_user_id, normalized_name);
CREATE INDEX idx_activity_record_user_time ON activity_records(user_id, occurred_at);
CREATE INDEX idx_activity_record_active_time ON activity_records(user_id, deleted_at, occurred_at);

INSERT INTO activity_types
  (id,uniqueness_scope,name,normalized_name,category,low_met,medium_met,high_met,type_scope)
VALUES
  ('act-walking','SYSTEM','步行','步行','CARDIO',2.50,3.50,5.00,'SYSTEM'),
  ('act-running','SYSTEM','跑步','跑步','CARDIO',6.00,8.30,11.00,'SYSTEM'),
  ('act-cycling','SYSTEM','骑行','骑行','CARDIO',4.00,6.80,10.00,'SYSTEM'),
  ('act-swimming','SYSTEM','游泳','游泳','CARDIO',4.80,7.00,9.80,'SYSTEM'),
  ('act-rope-skipping','SYSTEM','跳绳','跳绳','CARDIO',8.30,11.80,12.30,'SYSTEM'),
  ('act-strength','SYSTEM','力量训练','力量训练','STRENGTH',3.50,5.00,6.00,'SYSTEM'),
  ('act-yoga','SYSTEM','瑜伽','瑜伽','FLEXIBILITY',2.00,2.80,4.00,'SYSTEM'),
  ('act-badminton','SYSTEM','羽毛球','羽毛球','SPORT',4.50,5.50,7.00,'SYSTEM'),
  ('act-basketball','SYSTEM','篮球','篮球','SPORT',4.50,6.50,8.00,'SYSTEM'),
  ('act-football','SYSTEM','足球','足球','SPORT',5.00,7.00,10.00,'SYSTEM'),
  ('act-aerobics','SYSTEM','健身操','健身操','CARDIO',4.00,6.50,8.50,'SYSTEM'),
  ('act-hiking','SYSTEM','爬山','爬山','CARDIO',4.00,6.00,8.00,'SYSTEM'),
  ('act-elliptical','SYSTEM','椭圆机','椭圆机','CARDIO',4.00,5.00,8.00,'SYSTEM'),
  ('act-rowing','SYSTEM','划船机','划船机','CARDIO',4.50,7.00,8.50,'SYSTEM');
