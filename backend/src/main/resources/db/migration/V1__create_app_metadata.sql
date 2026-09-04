CREATE TABLE app_metadata (
  metadata_key VARCHAR(64) PRIMARY KEY,
  metadata_value VARCHAR(255) NOT NULL,
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
);

INSERT INTO app_metadata (metadata_key, metadata_value)
VALUES ('schema_version', '1');
