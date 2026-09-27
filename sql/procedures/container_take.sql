CREATE OR REPLACE PROCEDURE container_take(IN p_item_id INT, IN p_char_id INT)
BEGIN
  DECLARE v_cont INT DEFAULT NULL;
  DECLARE v_slot INT DEFAULT NULL;
  DECLARE v_owner_char INT DEFAULT NULL;
  DECLARE v_owner_item INT DEFAULT NULL;
  DECLARE v_owner_holder INT DEFAULT NULL;
  DECLARE v_held INT DEFAULT 0;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  SELECT container_id, slot INTO v_cont, v_slot FROM items WHERE id = p_item_id FOR UPDATE;
  IF v_cont IS NULL THEN
    ROLLBACK;
    SELECT 0 AS ok, 'NOT_IN_CONTAINER' AS code, NULL AS payload;
  ELSE
    SELECT owner_char_id, owner_item_id INTO v_owner_char, v_owner_item FROM containers WHERE id = v_cont FOR UPDATE;
    IF v_owner_item IS NOT NULL THEN
      SELECT holder_char_id INTO v_owner_holder FROM items WHERE id = v_owner_item;
    END IF;
    SELECT COUNT(*) INTO v_held FROM items WHERE holder_char_id = p_char_id AND holder_kind = 'held' FOR UPDATE;
    IF NOT (v_owner_char <=> p_char_id OR v_owner_holder <=> p_char_id) THEN
      ROLLBACK;
      SELECT 0 AS ok, 'NOT_OWNER' AS code, NULL AS payload;
    ELSEIF v_held > 0 THEN
      ROLLBACK;
      SELECT 0 AS ok, 'HANDS_FULL' AS code, NULL AS payload;
    ELSE
      UPDATE items SET container_id = NULL, slot = NULL, holder_char_id = p_char_id, holder_kind = 'held' WHERE id = p_item_id;
      UPDATE items SET slot = slot - 1 WHERE container_id = v_cont AND slot > v_slot ORDER BY slot ASC;
      COMMIT;
      SELECT 1 AS ok, 'OK' AS code, JSON_OBJECT('item_id', CAST(p_item_id AS SIGNED), 'container_id', CAST(v_cont AS SIGNED)) AS payload;
    END IF;
  END IF;
END
