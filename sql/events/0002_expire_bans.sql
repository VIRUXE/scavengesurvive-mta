CREATE OR REPLACE EVENT ev_expire_bans ON SCHEDULE EVERY 1 MINUTE DO
  UPDATE bans SET active = 0 WHERE active = 1 AND expires_at IS NOT NULL AND expires_at < NOW()
