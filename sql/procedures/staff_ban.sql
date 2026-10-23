CREATE OR REPLACE PROCEDURE staff_ban(IN p_name VARCHAR(24), IN p_account_id INT, IN p_ip VARCHAR(45), IN p_serial CHAR(32),
                                      IN p_reason VARCHAR(128), IN p_by_account_id INT, IN p_by_name VARCHAR(24), IN p_seconds INT)
BEGIN
  DECLARE v_id INT DEFAULT 0;
  DECLARE v_expires DATETIME DEFAULT NULL;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  IF EXISTS (SELECT 1 FROM bans WHERE name = p_name AND active = 1 AND (expires_at IS NULL OR expires_at > NOW()) FOR UPDATE) THEN
    ROLLBACK;
    SELECT 0 AS ok, 'ALREADY_BANNED' AS code, NULL AS payload;
  ELSE
    IF p_seconds > 0 THEN
      SET v_expires = NOW() + INTERVAL p_seconds SECOND;
    END IF;
    INSERT INTO bans (account_id, name, ip, serial, reason, by_account_id, by_name, expires_at)
      VALUES (p_account_id, p_name, p_ip, p_serial, p_reason, p_by_account_id, p_by_name, v_expires);
    SET v_id = LAST_INSERT_ID();
    INSERT INTO staff_actions (actor_account_id, actor_name, action, target_name, target_account_id, details)
      VALUES (p_by_account_id, p_by_name, 'ban', p_name, p_account_id,
              CONCAT(p_reason, ' (', IF(v_expires IS NULL, 'forever', CONCAT('until ', DATE_FORMAT(v_expires, '%Y-%m-%d %H:%i'))), ')'));
    COMMIT;
    SELECT 1 AS ok, 'OK' AS code,
           JSON_OBJECT('ban_id', CAST(v_id AS SIGNED), 'expires_at', DATE_FORMAT(v_expires, '%Y-%m-%d %H:%i:%s')) AS payload;
  END IF;
END
