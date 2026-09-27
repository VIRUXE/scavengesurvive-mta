CREATE OR REPLACE PROCEDURE item_pickup(IN p_item_id INT, IN p_char_id INT)
BEGIN
  DECLARE v_alive INT DEFAULT 0;
  DECLARE v_held INT DEFAULT 0;
  DECLARE v_rows INT DEFAULT 0;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  SELECT COUNT(*) INTO v_alive FROM characters WHERE id = p_char_id AND alive = 1 FOR UPDATE;
  SELECT COUNT(*) INTO v_held FROM items WHERE holder_char_id = p_char_id AND holder_kind = 'held' FOR UPDATE;
  IF v_alive = 0 THEN
    ROLLBACK;
    SELECT 0 AS ok, 'NO_CHARACTER' AS code, NULL AS payload;
  ELSEIF v_held > 0 THEN
    ROLLBACK;
    SELECT 0 AS ok, 'HANDS_FULL' AS code, NULL AS payload;
  ELSE
    UPDATE items SET holder_char_id = p_char_id, holder_kind = 'held', x = NULL, y = NULL, z = NULL, rz = NULL,
      interior = NULL, dimension = NULL, loot_spawn_id = NULL, despawn_at = NULL
      WHERE id = p_item_id AND x IS NOT NULL;
    SET v_rows = ROW_COUNT();
    IF v_rows = 0 THEN
      ROLLBACK;
      SELECT 0 AS ok, 'NOT_IN_WORLD' AS code, NULL AS payload;
    ELSE
      DELETE FROM world_items_pos WHERE item_id = p_item_id;
      COMMIT;
      SELECT 1 AS ok, 'OK' AS code, JSON_OBJECT('item_id', CAST(p_item_id AS SIGNED)) AS payload;
    END IF;
  END IF;
END
