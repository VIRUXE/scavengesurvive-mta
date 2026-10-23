-- Milestone M8: chat modes and the radio (upstream player file CHAR cells "radio freq" and "chatmode").

ALTER TABLE characters ADD COLUMN IF NOT EXISTS radio_freq FLOAT NOT NULL DEFAULT 98.12 AFTER dimension;

ALTER TABLE characters ADD COLUMN IF NOT EXISTS chat_mode TINYINT NOT NULL DEFAULT 0 AFTER radio_freq;

INSERT INTO schema_migrations (version, name) VALUES (8, 'chat_m8') ON DUPLICATE KEY UPDATE name = VALUES(name);
