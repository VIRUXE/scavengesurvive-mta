CREATE OR REPLACE PROCEDURE clothes_swap(IN p_item_id INT, IN p_char_id INT, IN p_new_skin SMALLINT)
BEGIN
  DECLARE v_old SMALLINT DEFAULT NULL;
  DECLARE v_type VARCHAR(32) DEFAULT NULL;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  SELECT skin INTO v_old FROM characters WHERE id = p_char_id AND alive = 1 FOR UPDATE;
  -- p_char_id IS NOT NULL: with <=> a NULL caller would otherwise match unowned (world) items
  SELECT i.type_uname INTO v_type FROM items i
    LEFT JOIN containers c ON c.id = i.container_id
    LEFT JOIN items owner ON owner.id = c.owner_item_id
    WHERE i.id = p_item_id AND p_char_id IS NOT NULL
      AND (i.holder_char_id <=> p_char_id OR c.owner_char_id <=> p_char_id OR owner.holder_char_id <=> p_char_id)
    FOR UPDATE;
  IF v_old IS NULL THEN
    ROLLBACK;
    SELECT 0 AS ok, 'NO_CHARACTER' AS code, NULL AS payload;
  ELSEIF v_type IS NULL OR v_type <> 'Clothes' THEN
    ROLLBACK;
    SELECT 0 AS ok, 'NOT_OWNED' AS code, NULL AS payload;
  ELSE
    -- upstream OnHoldActionFinish: the item now holds the clothes the character took off
    UPDATE items SET data = JSON_OBJECT('skin', CAST(v_old AS SIGNED)) WHERE id = p_item_id;
    UPDATE characters SET skin = p_new_skin WHERE id = p_char_id;
    COMMIT;
    SELECT 1 AS ok, 'OK' AS code, JSON_OBJECT('item_id', CAST(p_item_id AS SIGNED), 'old_skin', CAST(v_old AS SIGNED), 'new_skin', CAST(p_new_skin AS SIGNED)) AS payload;
  END IF;
END
