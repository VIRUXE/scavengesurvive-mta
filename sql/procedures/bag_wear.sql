CREATE OR REPLACE PROCEDURE bag_wear(IN p_item_id INT, IN p_char_id INT)
BEGIN
  DECLARE v_worn INT DEFAULT 0;
  DECLARE v_rows INT DEFAULT 0;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  SELECT COUNT(*) INTO v_worn FROM items WHERE holder_char_id = p_char_id AND holder_kind = 'bag' FOR UPDATE;
  IF v_worn > 0 THEN
    ROLLBACK;
    SELECT 0 AS ok, 'BAG_SLOT_USED' AS code, NULL AS payload;
  ELSE
    UPDATE items SET holder_kind = 'bag' WHERE id = p_item_id AND holder_char_id = p_char_id AND holder_kind = 'held';
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
