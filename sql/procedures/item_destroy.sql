CREATE OR REPLACE PROCEDURE item_destroy(IN p_item_id INT, IN p_char_id INT)
BEGIN
  DECLARE v_rows INT DEFAULT 0;
  DECLARE v_cont INT DEFAULT NULL;
  DECLARE v_slot INT DEFAULT NULL;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  SELECT container_id, slot INTO v_cont, v_slot FROM items WHERE id = p_item_id FOR UPDATE;
  -- p_char_id IS NOT NULL: with <=> a NULL caller would otherwise match unowned (world) items
  DELETE i FROM items i
    LEFT JOIN containers c ON c.id = i.container_id
    LEFT JOIN items owner ON owner.id = c.owner_item_id
    WHERE i.id = p_item_id AND p_char_id IS NOT NULL
      AND (i.holder_char_id <=> p_char_id OR c.owner_char_id <=> p_char_id OR owner.holder_char_id <=> p_char_id);
  SET v_rows = ROW_COUNT();
  IF v_rows = 0 THEN
    ROLLBACK;
    SELECT 0 AS ok, 'NOT_OWNED' AS code, NULL AS payload;
  ELSE
    IF v_cont IS NOT NULL THEN
      UPDATE items SET slot = slot - 1 WHERE container_id = v_cont AND slot > v_slot ORDER BY slot ASC;
    END IF;
    COMMIT;
    SELECT 1 AS ok, 'OK' AS code, JSON_OBJECT('item_id', CAST(p_item_id AS SIGNED)) AS payload;
  END IF;
END
