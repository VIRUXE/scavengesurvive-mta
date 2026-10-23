-- Milestone M7: Staff & Ops. Bans, whitelist, reports, staff action log, account warnings and mutes.
-- Upstream: gamemodes/sss/core/admin/{ban,report,mute,admin}.pwn and core/player/whitelist.pwn (SQLite);
-- bans gain a serial (upstream had none, ADR 0007 "fix known upstream bugs") and an expiry timestamp instead
-- of date + duration.

-- accounts is WITH SYSTEM VERSIONING: MariaDB refuses ALTER TABLE on it (error 4119) unless the session opts in.
-- KEEP leaves the history rows in place; the new columns read as their defaults for old versions.
SET SESSION system_versioning_alter_history = KEEP;

ALTER TABLE accounts ADD COLUMN IF NOT EXISTS warnings TINYINT NOT NULL DEFAULT 0 AFTER active;

ALTER TABLE accounts ADD COLUMN IF NOT EXISTS muted TINYINT(1) NOT NULL DEFAULT 0 AFTER warnings;

ALTER TABLE accounts ADD COLUMN IF NOT EXISTS mute_until DATETIME NULL AFTER muted;

CREATE TABLE IF NOT EXISTS bans (
  id INT AUTO_INCREMENT PRIMARY KEY,
  account_id INT NULL,
  name VARCHAR(24) NOT NULL,
  ip VARCHAR(45) NULL,
  serial CHAR(32) NULL,
  reason VARCHAR(128) NOT NULL DEFAULT '',
  by_account_id INT NULL,
  by_name VARCHAR(24) NOT NULL DEFAULT 'Server',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at DATETIME NULL,
  active TINYINT(1) NOT NULL DEFAULT 1,
  KEY ix_bans_name (name, active),
  KEY ix_bans_ip (ip, active),
  KEY ix_bans_serial (serial, active),
  KEY ix_bans_expiry (active, expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci WITH SYSTEM VERSIONING;

CREATE TABLE IF NOT EXISTS whitelist (
  name VARCHAR(24) PRIMARY KEY,
  added_by VARCHAR(24) NOT NULL DEFAULT 'Server',
  added_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

CREATE TABLE IF NOT EXISTS reports (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(24) NOT NULL,
  reason VARCHAR(128) NOT NULL,
  type VARCHAR(10) NOT NULL DEFAULT 'PLY NAME',
  x FLOAT NULL,
  y FLOAT NULL,
  z FLOAT NULL,
  interior TINYINT NULL,
  dimension INT NULL,
  info VARCHAR(128) NULL,
  by_name VARCHAR(24) NOT NULL DEFAULT 'Server',
  by_account_id INT NULL,
  read_at DATETIME NULL,
  active TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY ix_reports_active (active, created_at),
  KEY ix_reports_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

CREATE TABLE IF NOT EXISTS staff_actions (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  actor_account_id INT NULL,
  actor_name VARCHAR(24) NOT NULL,
  action VARCHAR(32) NOT NULL,
  target_name VARCHAR(24) NULL,
  target_account_id INT NULL,
  details VARCHAR(255) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY ix_staff_actions_actor (actor_account_id, created_at),
  KEY ix_staff_actions_target (target_name, created_at),
  KEY ix_staff_actions_action (action, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

INSERT INTO schema_migrations (version, name) VALUES (6, 'staff_m7') ON DUPLICATE KEY UPDATE name = VALUES(name);
