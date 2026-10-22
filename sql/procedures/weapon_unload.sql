CREATE OR REPLACE PROCEDURE weapon_unload(
  IN p_char_id INT, IN p_weapon_id INT, IN p_weapon_data JSON,
  IN p_ammo_uname VARCHAR(32), IN p_ammo_data JSON,
  IN p_x FLOAT, IN p_y FLOAT, IN p_z FLOAT, IN p_rz FLOAT,
  IN p_interior TINYINT, IN p_dimension INT)
BEGIN
  DECLARE v_held_ok INT DEFAULT 0;
  DECLARE v_cat VARCHAR(16) DEFAULT NULL;
  DECLARE v_ammo_id INT DEFAULT 0;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SELECT category INTO v_cat FROM item_types WHERE uname = p_ammo_uname;
  IF v_cat IS NULL THEN
    SELECT 0 AS ok, 'UNKNOWN_TYPE' AS code, NULL AS payload;
  ELSE
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SELECT COUNT(*) INTO v_held_ok FROM items
      WHERE id = p_weapon_id AND holder_char_id = p_char_id AND holder_kind = 'held' FOR UPDATE;
    IF v_held_ok = 0 THEN
      ROLLBACK;
      SELECT 0 AS ok, 'NOT_HELD' AS code, NULL AS payload;
    ELSE
      UPDATE items SET data = p_weapon_data WHERE id = p_weapon_id;
      INSERT INTO items (type_uname, hitpoints, data, x, y, z, rz, interior, dimension)
        VALUES (p_ammo_uname, 5, p_ammo_data, p_x, p_y, p_z, p_rz, p_interior, p_dimension);
      SET v_ammo_id = LAST_INSERT_ID();
      INSERT INTO world_items_pos (item_id, pos) VALUES (v_ammo_id, POINT(p_x, p_y));
      COMMIT;
      SELECT 1 AS ok, 'OK' AS code, JSON_OBJECT(
        'weapon_id', CAST(p_weapon_id AS SIGNED),
        'ammo_item_id', CAST(v_ammo_id AS SIGNED)
      ) AS payload;
    END IF;
  END IF;
END
