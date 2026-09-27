CREATE TABLE IF NOT EXISTS schema_migrations (
  version INT PRIMARY KEY,
  name VARCHAR(80) NOT NULL,
  applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS accounts (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(24) NOT NULL,
  password_hash CHAR(60) NOT NULL,
  admin_level TINYINT NOT NULL DEFAULT 0,
  lang VARCHAR(8) NOT NULL DEFAULT 'en',
  registered_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_login_at DATETIME NULL,
  last_ip VARCHAR(45) NULL,
  last_serial CHAR(32) NULL,
  active TINYINT(1) NOT NULL DEFAULT 1,
  UNIQUE KEY uq_accounts_name (name),
  KEY ix_accounts_serial (last_serial)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci WITH SYSTEM VERSIONING;

CREATE TABLE IF NOT EXISTS item_types (
  uname VARCHAR(32) PRIMARY KEY,
  name VARCHAR(48) NOT NULL,
  model INT NOT NULL,
  size TINYINT NOT NULL DEFAULT 1,
  max_hitpoints SMALLINT NOT NULL DEFAULT 5,
  category ENUM('generic','weapon','ammo','food','liquid','bag','safebox') NOT NULL DEFAULT 'generic',
  category_data JSON NULL,
  CONSTRAINT chk_item_types_data CHECK (category_data IS NULL OR JSON_VALID(category_data))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS characters (
  id INT AUTO_INCREMENT PRIMARY KEY,
  account_id INT NOT NULL,
  alive TINYINT(1) NOT NULL DEFAULT 1,
  alive_account INT AS (IF(alive = 1, account_id, NULL)) STORED,
  skin SMALLINT NOT NULL,
  hp FLOAT NOT NULL DEFAULT 100,
  armour FLOAT NOT NULL DEFAULT 0,
  food FLOAT NOT NULL DEFAULT 80,
  bleed FLOAT NOT NULL DEFAULT 0,
  wounds JSON NOT NULL DEFAULT '[]',
  x FLOAT NOT NULL,
  y FLOAT NOT NULL,
  z FLOAT NOT NULL,
  rz FLOAT NOT NULL DEFAULT 0,
  interior TINYINT NOT NULL DEFAULT 0,
  dimension INT NOT NULL DEFAULT 0,
  inventory_container_id INT NULL,
  spawned_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  died_at DATETIME NULL,
  death_cause VARCHAR(32) NULL,
  killer_char_id INT NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_characters_alive_account (alive_account),
  KEY ix_characters_account (account_id),
  CONSTRAINT fk_characters_account FOREIGN KEY (account_id) REFERENCES accounts(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS containers (
  id INT AUTO_INCREMENT PRIMARY KEY,
  kind ENUM('inventory','bag','safebox','tent','vehicle','supply') NOT NULL,
  size TINYINT NOT NULL,
  owner_char_id INT NULL,
  owner_item_id INT NULL,
  UNIQUE KEY uq_containers_owner_item (owner_item_id),
  KEY ix_containers_owner_char (owner_char_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS items (
  id INT AUTO_INCREMENT PRIMARY KEY,
  type_uname VARCHAR(32) NOT NULL,
  hitpoints SMALLINT NOT NULL DEFAULT 5,
  data JSON NULL,
  x FLOAT NULL,
  y FLOAT NULL,
  z FLOAT NULL,
  rz FLOAT NULL,
  interior TINYINT NULL,
  dimension INT NULL,
  container_id INT NULL,
  slot TINYINT NULL,
  holder_char_id INT NULL,
  holder_kind ENUM('held','holster','bag','hat','mask','armour') NULL,
  loot_spawn_id INT NULL,
  despawn_at DATETIME NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_items_container_slot (container_id, slot),
  UNIQUE KEY uq_items_holder_kind (holder_char_id, holder_kind),
  KEY ix_items_loot_spawn (loot_spawn_id),
  KEY ix_items_despawn (despawn_at),
  KEY ix_items_type (type_uname),
  CONSTRAINT fk_items_type FOREIGN KEY (type_uname) REFERENCES item_types(uname),
  CONSTRAINT fk_items_container FOREIGN KEY (container_id) REFERENCES containers(id) ON DELETE CASCADE,
  CONSTRAINT chk_items_one_location CHECK (((x IS NOT NULL) + (container_id IS NOT NULL) + (holder_char_id IS NOT NULL)) = 1),
  CONSTRAINT chk_items_data CHECK (data IS NULL OR JSON_VALID(data))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 WITH SYSTEM VERSIONING;

ALTER TABLE containers ADD CONSTRAINT fk_containers_owner_item FOREIGN KEY (owner_item_id) REFERENCES items(id) ON DELETE CASCADE;

CREATE TABLE IF NOT EXISTS world_items_pos (
  item_id INT PRIMARY KEY,
  pos POINT NOT NULL,
  SPATIAL INDEX sp_world_items_pos (pos),
  CONSTRAINT fk_world_items_pos_item FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS loot_spawns (
  id INT AUTO_INCREMENT PRIMARY KEY,
  x FLOAT NOT NULL,
  y FLOAT NOT NULL,
  z FLOAT NOT NULL,
  table_name VARCHAR(32) NOT NULL,
  weight FLOAT NOT NULL,
  size TINYINT NOT NULL DEFAULT -1,
  interior TINYINT NOT NULL DEFAULT 0,
  dimension INT NOT NULL DEFAULT 0,
  zone VARCHAR(8) NOT NULL,
  enabled TINYINT(1) NOT NULL DEFAULT 1,
  pos POINT NOT NULL,
  SPATIAL INDEX sp_loot_spawns_pos (pos),
  KEY ix_loot_spawns_zone (zone)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS loot_spawn_state (
  spawn_id INT PRIMARY KEY,
  next_roll_at DATETIME NOT NULL,
  KEY ix_loot_spawn_state_due (next_roll_at),
  CONSTRAINT fk_loot_spawn_state_spawn FOREIGN KEY (spawn_id) REFERENCES loot_spawns(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS settings (
  skey VARCHAR(48) PRIMARY KEY,
  svalue VARCHAR(255) NOT NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS connection_log (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  account_id INT NULL,
  name VARCHAR(24) NOT NULL,
  serial CHAR(32) NULL,
  ip VARCHAR(45) NULL,
  joined_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  left_at DATETIME NULL,
  KEY ix_connection_log_serial (serial),
  KEY ix_connection_log_account (account_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO schema_migrations (version, name) VALUES (1, 'init') ON DUPLICATE KEY UPDATE name = VALUES(name);
