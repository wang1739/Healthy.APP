ALTER TABLE health_plan_versions
  ADD COLUMN status VARCHAR(16) NOT NULL DEFAULT 'HISTORY';

UPDATE health_plan_versions
SET status = 'ACTIVE'
WHERE EXISTS (
  SELECT 1 FROM health_plans
  WHERE health_plans.id = health_plan_versions.plan_id
    AND health_plans.current_version = health_plan_versions.version_number
);

ALTER TABLE health_plan_versions
  ADD CONSTRAINT ck_plan_version_status CHECK (status IN ('HISTORY', 'ACTIVE', 'PREVIEW'));

CREATE INDEX idx_plan_version_status
  ON health_plan_versions(plan_id, status, version_number);
