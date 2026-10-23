-- Milestone M8: supply drop and weapons cache points (upstream DefineSupplyDropPos / DefineWeaponsCachePos in
-- gamemodes/sss/world/zones/*.pwn, seeded by tools/convert/zones.py into sql/seed/0005_drop_points.sql).
-- used_at marks a point that dropped recently; the seed clears it on every apply, like upstream's per-start reset.

CREATE TABLE IF NOT EXISTS supply_drop_points (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(32) NOT NULL,
  x FLOAT NOT NULL,
  y FLOAT NOT NULL,
  z FLOAT NOT NULL,
  zone VARCHAR(8) NOT NULL,
  used_at DATETIME NULL,
  KEY ix_supply_drop_points_used (used_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS weapon_cache_points (
  id INT AUTO_INCREMENT PRIMARY KEY,
  x FLOAT NOT NULL,
  y FLOAT NOT NULL,
  z FLOAT NOT NULL,
  zone VARCHAR(8) NOT NULL,
  used_at DATETIME NULL,
  KEY ix_weapon_cache_points_used (used_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO schema_migrations (version, name) VALUES (7, 'drop_points_m8') ON DUPLICATE KEY UPDATE name = VALUES(name);
