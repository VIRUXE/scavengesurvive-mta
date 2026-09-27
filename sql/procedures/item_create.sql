CREATE OR REPLACE PROCEDURE item_create(
  IN p_type_uname VARCHAR(32), IN p_hitpoints SMALLINT, IN p_data JSON,
  IN p_x FLOAT, IN p_y FLOAT, IN p_z FLOAT, IN p_rz FLOAT, IN p_interior TINYINT, IN p_dimension INT,
  IN p_loot_spawn_id INT, IN p_despawn_at DATETIME)
BEGIN
  DECLARE v_item INT;
  DECLARE v_cont INT DEFAULT NULL;
  DECLARE v_cat VARCHAR(16) DEFAULT NULL;
  DECLARE v_size INT DEFAULT NULL;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SELECT category, JSON_VALUE(category_data, '$.bag_size') INTO v_cat, v_size FROM item_types WHERE uname = p_type_uname;
  IF v_cat IS NULL THEN
    SELECT 0 AS ok, 'UNKNOWN_TYPE' AS code, NULL AS payload;
  ELSE
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    INSERT INTO items (type_uname, hitpoints, data, x, y, z, rz, interior, dimension, loot_spawn_id, despawn_at)
      VALUES (p_type_uname, IFNULL(p_hitpoints, 5), p_data, p_x, p_y, p_z, p_rz, p_interior, p_dimension, p_loot_spawn_id, p_despawn_at);
    SET v_item = LAST_INSERT_ID();
    INSERT INTO world_items_pos (item_id, pos) VALUES (v_item, POINT(p_x, p_y));
    IF v_cat IN ('bag', 'safebox') THEN
      INSERT INTO containers (kind, size, owner_item_id) VALUES (v_cat, IFNULL(v_size, 8), v_item);
      SET v_cont = LAST_INSERT_ID();
    END IF;
    COMMIT;
    SELECT 1 AS ok, 'OK' AS code, JSON_OBJECT('item_id', CAST(v_item AS SIGNED), 'container_id', CAST(v_cont AS SIGNED)) AS payload;
  END IF;
END
