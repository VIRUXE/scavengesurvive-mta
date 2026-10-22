CREATE OR REPLACE PROCEDURE item_disarm(
  IN p_actor_char_id INT, IN p_target_char_id INT, IN p_item_id INT)
BEGIN
  DECLARE v_actor_alive INT DEFAULT 0;
  DECLARE v_actor_held INT DEFAULT 0;
  DECLARE v_rows INT DEFAULT 0;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  SELECT COUNT(*) INTO v_actor_alive FROM characters WHERE id = p_actor_char_id AND alive = 1 FOR UPDATE;
  SELECT COUNT(*) INTO v_actor_held FROM items WHERE holder_char_id = p_actor_char_id AND holder_kind = 'held' FOR UPDATE;
  IF v_actor_alive = 0 THEN
    ROLLBACK;
    SELECT 0 AS ok, 'NO_CHARACTER' AS code, NULL AS payload;
  ELSEIF v_actor_held > 0 THEN
    ROLLBACK;
    SELECT 0 AS ok, 'HANDS_FULL' AS code, NULL AS payload;
  ELSE
    UPDATE items SET holder_char_id = p_actor_char_id
      WHERE id = p_item_id AND holder_char_id = p_target_char_id AND holder_kind = 'held';
    SET v_rows = ROW_COUNT();
    IF v_rows = 0 THEN
      ROLLBACK;
      SELECT 0 AS ok, 'NOT_HELD' AS code, NULL AS payload;
    ELSE
      COMMIT;
      SELECT 1 AS ok, 'OK' AS code, JSON_OBJECT('item_id', CAST(p_item_id AS SIGNED)) AS payload;
    END IF;
  END IF;
END
