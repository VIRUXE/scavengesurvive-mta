CREATE OR REPLACE PROCEDURE item_create_held(
  IN p_type_uname VARCHAR(32), IN p_char_id INT)
BEGIN
  DECLARE v_alive INT DEFAULT 0;
  DECLARE v_held INT DEFAULT 0;
  DECLARE v_cat VARCHAR(16) DEFAULT NULL;
  DECLARE v_item INT DEFAULT 0;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SELECT category INTO v_cat FROM item_types WHERE uname = p_type_uname;
  IF v_cat IS NULL THEN
    SELECT 0 AS ok, 'UNKNOWN_TYPE' AS code, NULL AS payload;
  ELSE
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
      INSERT INTO items (type_uname, hitpoints, holder_char_id, holder_kind)
        VALUES (p_type_uname, 5, p_char_id, 'held');
      SET v_item = LAST_INSERT_ID();
      COMMIT;
      SELECT 1 AS ok, 'OK' AS code, JSON_OBJECT('item_id', CAST(v_item AS SIGNED)) AS payload;
    END IF;
  END IF;
END
