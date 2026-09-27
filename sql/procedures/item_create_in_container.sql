CREATE OR REPLACE PROCEDURE item_create_in_container(IN p_type_uname VARCHAR(32), IN p_container_id INT)
BEGIN
  DECLARE v_cat VARCHAR(16) DEFAULT NULL;
  DECLARE v_item_size INT DEFAULT 1;
  DECLARE v_bag_size INT DEFAULT NULL;
  DECLARE v_size INT DEFAULT NULL;
  DECLARE v_used INT DEFAULT 0;
  DECLARE v_slot INT DEFAULT 0;
  DECLARE v_item INT;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SELECT category, size, JSON_VALUE(category_data, '$.bag_size') INTO v_cat, v_item_size, v_bag_size
    FROM item_types WHERE uname = p_type_uname;
  IF v_cat IS NULL THEN
    SELECT 0 AS ok, 'UNKNOWN_TYPE' AS code, NULL AS payload;
  ELSE
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SELECT size INTO v_size FROM containers WHERE id = p_container_id FOR UPDATE;
    IF v_size IS NULL THEN
      ROLLBACK;
      SELECT 0 AS ok, 'NO_CONTAINER' AS code, NULL AS payload;
    ELSE
      SELECT IFNULL(SUM(t.size), 0), IFNULL(MAX(i.slot) + 1, 0) INTO v_used, v_slot
        FROM items i JOIN item_types t ON t.uname = i.type_uname WHERE i.container_id = p_container_id FOR UPDATE;
      IF v_used + v_item_size > v_size THEN
        ROLLBACK;
        SELECT 0 AS ok, 'CONTAINER_FULL' AS code, NULL AS payload;
      ELSE
        INSERT INTO items (type_uname, hitpoints, container_id, slot) VALUES (p_type_uname, 5, p_container_id, v_slot);
        SET v_item = LAST_INSERT_ID();
        IF v_cat IN ('bag', 'safebox') THEN
          INSERT INTO containers (kind, size, owner_item_id) VALUES (v_cat, IFNULL(v_bag_size, 8), v_item);
        END IF;
        COMMIT;
        SELECT 1 AS ok, 'OK' AS code, JSON_OBJECT('item_id', CAST(v_item AS SIGNED), 'slot', CAST(v_slot AS SIGNED)) AS payload;
      END IF;
    END IF;
  END IF;
END
