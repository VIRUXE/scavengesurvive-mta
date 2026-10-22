CREATE TABLE IF NOT EXISTS vehicle_spawns (
  id INT AUTO_INCREMENT PRIMARY KEY,
  x FLOAT NOT NULL,
  y FLOAT NOT NULL,
  z FLOAT NOT NULL,
  rz FLOAT NOT NULL,
  group_name VARCHAR(16) NULL,
  type_name VARCHAR(32) NULL,
  categories VARCHAR(8) NOT NULL DEFAULT '',
  sizes VARCHAR(3) NOT NULL DEFAULT '',
  file VARCHAR(48) NOT NULL,
  enabled TINYINT(1) NOT NULL DEFAULT 1,
  pos POINT NOT NULL,
  SPATIAL INDEX sp_vehicle_spawns_pos (pos),
  KEY ix_vehicle_spawns_file (file),
  CONSTRAINT ck_vehicle_spawns_target CHECK ((group_name IS NULL) <> (type_name IS NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO schema_migrations (version, name) VALUES (2, 'vehicle_spawns') ON DUPLICATE KEY UPDATE name = VALUES(name);
