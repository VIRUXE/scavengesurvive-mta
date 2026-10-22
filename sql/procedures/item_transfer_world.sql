CREATE OR REPLACE PROCEDURE item_transfer_world(
  IN p_char_id INT, IN p_held_id INT, IN p_world_id INT,
  IN p_held_data JSON, IN p_world_data JSON,
  IN p_delete_world TINYINT, IN p_delete_held TINYINT)
BEGIN
  DECLARE v_held_ok INT DEFAULT 0;
  DECLARE v_world_ok INT DEFAULT 0;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  SELECT COUNT(*) INTO v_held_ok FROM items
    WHERE id = p_held_id AND holder_char_id = p_char_id AND holder_kind = 'held' FOR UPDATE;
  SELECT COUNT(*) INTO v_world_ok FROM items
    WHERE id = p_world_id AND x IS NOT NULL FOR UPDATE;
  IF v_held_ok = 0 THEN
    ROLLBACK;
    SELECT 0 AS ok, 'NOT_HELD' AS code, NULL AS payload;
  ELSEIF v_world_ok = 0 THEN
    ROLLBACK;
    SELECT 0 AS ok, 'NOT_IN_WORLD' AS code, NULL AS payload;
  ELSE
    IF p_delete_held = 1 THEN
      DELETE FROM items WHERE id = p_held_id;
    ELSE
      UPDATE items SET data = p_held_data WHERE id = p_held_id;
    END IF;
    IF p_delete_world = 1 THEN
      DELETE FROM world_items_pos WHERE item_id = p_world_id;
      DELETE FROM items WHERE id = p_world_id;
    ELSE
      UPDATE items SET data = p_world_data WHERE id = p_world_id;
    END IF;
    COMMIT;
    SELECT 1 AS ok, 'OK' AS code, JSON_OBJECT(
      'held_id', CAST(p_held_id AS SIGNED),
      'world_id', CAST(p_world_id AS SIGNED),
      'deleted_world', CAST(p_delete_world AS SIGNED),
      'deleted_held', CAST(p_delete_held AS SIGNED)
    ) AS payload;
  END IF;
END
