CREATE OR REPLACE PROCEDURE staff_unban(IN p_name VARCHAR(24), IN p_by_account_id INT, IN p_by_name VARCHAR(24))
BEGIN
  DECLARE v_n INT DEFAULT 0;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  UPDATE bans SET active = 0 WHERE name = p_name AND active = 1;
  SET v_n = ROW_COUNT();
  IF v_n = 0 THEN
    ROLLBACK;
    SELECT 0 AS ok, 'NOT_BANNED' AS code, NULL AS payload;
  ELSE
    INSERT INTO staff_actions (actor_account_id, actor_name, action, target_name, details)
      VALUES (p_by_account_id, p_by_name, 'unban', p_name, CONCAT(v_n, ' ban(s) lifted'));
    COMMIT;
    SELECT 1 AS ok, 'OK' AS code, JSON_OBJECT('lifted', CAST(v_n AS SIGNED)) AS payload;
  END IF;
END
