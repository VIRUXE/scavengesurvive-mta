CREATE OR REPLACE PROCEDURE container_put(IN p_item_id INT, IN p_char_id INT, IN p_container_id INT)
BEGIN
  DECLARE v_owner_char INT DEFAULT NULL;
  DECLARE v_owner_item INT DEFAULT NULL;
  DECLARE v_owner_holder INT DEFAULT NULL;
  DECLARE v_size INT DEFAULT NULL;
  DECLARE v_used INT DEFAULT 0;
  DECLARE v_item_size INT DEFAULT 1;
  DECLARE v_held INT DEFAULT 0;
  DECLARE v_slot INT DEFAULT 0;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  SELECT owner_char_id, owner_item_id, size INTO v_owner_char, v_owner_item, v_size
    FROM containers WHERE id = p_container_id FOR UPDATE;
  SELECT COUNT(*) INTO v_held FROM items WHERE id = p_item_id AND holder_char_id = p_char_id AND holder_kind = 'held' FOR UPDATE;
  SELECT t.size INTO v_item_size FROM items i JOIN item_types t ON t.uname = i.type_uname WHERE i.id = p_item_id;
  IF v_owner_item IS NOT NULL THEN
    SELECT holder_char_id INTO v_owner_holder FROM items WHERE id = v_owner_item;
  END IF;
  IF v_size IS NULL OR v_held = 0 THEN
    ROLLBACK;
    SELECT 0 AS ok, 'NOT_HELD' AS code, NULL AS payload;
  ELSEIF v_owner_item = p_item_id THEN
    ROLLBACK;
    SELECT 0 AS ok, 'SELF_CONTAINMENT' AS code, NULL AS payload;
  ELSEIF NOT (v_owner_char <=> p_char_id OR v_owner_holder <=> p_char_id) THEN
    ROLLBACK;
    SELECT 0 AS ok, 'NOT_OWNER' AS code, NULL AS payload;
  ELSE
    SELECT IFNULL(SUM(t.size), 0), IFNULL(MAX(i.slot) + 1, 0) INTO v_used, v_slot
      FROM items i JOIN item_types t ON t.uname = i.type_uname WHERE i.container_id = p_container_id FOR UPDATE;
    IF v_used + v_item_size > v_size THEN
      ROLLBACK;
      SELECT 0 AS ok, 'CONTAINER_FULL' AS code, JSON_OBJECT('used', CAST(v_used AS SIGNED), 'size', CAST(v_size AS SIGNED)) AS payload;
    ELSE
      UPDATE items SET holder_char_id = NULL, holder_kind = NULL, container_id = p_container_id, slot = v_slot WHERE id = p_item_id;
      COMMIT;
      SELECT 1 AS ok, 'OK' AS code, JSON_OBJECT('slot', CAST(v_slot AS SIGNED), 'container_id', CAST(p_container_id AS SIGNED)) AS payload;
    END IF;
  END IF;
END
