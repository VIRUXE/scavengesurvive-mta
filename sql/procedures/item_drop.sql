CREATE OR REPLACE PROCEDURE item_drop(IN p_item_id INT, IN p_char_id INT, IN p_x FLOAT, IN p_y FLOAT, IN p_z FLOAT,
  IN p_rz FLOAT, IN p_interior TINYINT, IN p_dimension INT)
BEGIN
  DECLARE v_rows INT DEFAULT 0;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  UPDATE items SET holder_char_id = NULL, holder_kind = NULL, x = p_x, y = p_y, z = p_z, rz = p_rz,
    interior = p_interior, dimension = p_dimension
    WHERE id = p_item_id AND holder_char_id = p_char_id AND holder_kind = 'held';
  SET v_rows = ROW_COUNT();
  IF v_rows = 0 THEN
    ROLLBACK;
    SELECT 0 AS ok, 'NOT_HELD' AS code, NULL AS payload;
  ELSE
    INSERT INTO world_items_pos (item_id, pos) VALUES (p_item_id, POINT(p_x, p_y));
    COMMIT;
    SELECT 1 AS ok, 'OK' AS code, JSON_OBJECT('item_id', CAST(p_item_id AS SIGNED)) AS payload;
  END IF;
END
