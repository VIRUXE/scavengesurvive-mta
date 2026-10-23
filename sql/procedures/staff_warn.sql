CREATE OR REPLACE PROCEDURE staff_warn(IN p_account_id INT, IN p_name VARCHAR(24), IN p_ip VARCHAR(45), IN p_serial CHAR(32),
                                       IN p_by_account_id INT, IN p_by_name VARCHAR(24), IN p_reason VARCHAR(128),
                                       IN p_max INT, IN p_ban_seconds INT)
BEGIN
  DECLARE v_warnings INT DEFAULT NULL;
  DECLARE v_ban_id INT DEFAULT 0;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  SELECT warnings INTO v_warnings FROM accounts WHERE id = p_account_id FOR UPDATE;
  IF v_warnings IS NULL THEN
    ROLLBACK;
    SELECT 0 AS ok, 'NO_ACCOUNT' AS code, NULL AS payload;
  ELSE
    SET v_warnings = v_warnings + 1;
    INSERT INTO staff_actions (actor_account_id, actor_name, action, target_name, target_account_id, details)
      VALUES (p_by_account_id, p_by_name, 'warn', p_name, p_account_id, CONCAT(v_warnings, '/', p_max, ': ', p_reason));
    IF v_warnings >= p_max THEN
      -- upstream level1.pwn: the fifth warning is a one-day ban; the counter starts again afterwards
      INSERT INTO bans (account_id, name, ip, serial, reason, by_account_id, by_name, expires_at)
        VALUES (p_account_id, p_name, p_ip, p_serial, CONCAT('Getting ', p_max, ' warnings'), p_by_account_id, p_by_name,
                IF(p_ban_seconds > 0, NOW() + INTERVAL p_ban_seconds SECOND, NULL));
      SET v_ban_id = LAST_INSERT_ID();
      INSERT INTO staff_actions (actor_account_id, actor_name, action, target_name, target_account_id, details)
        VALUES (p_by_account_id, p_by_name, 'ban', p_name, p_account_id, CONCAT('Getting ', p_max, ' warnings'));
      UPDATE accounts SET warnings = 0 WHERE id = p_account_id;
    ELSE
      UPDATE accounts SET warnings = v_warnings WHERE id = p_account_id;
    END IF;
    COMMIT;
    SELECT 1 AS ok, 'OK' AS code,
           JSON_OBJECT('warnings', CAST(v_warnings AS SIGNED), 'banned', CAST(v_ban_id > 0 AS SIGNED),
                       'ban_id', CAST(v_ban_id AS SIGNED)) AS payload;
  END IF;
END
