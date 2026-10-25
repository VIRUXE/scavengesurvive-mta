CREATE OR REPLACE PROCEDURE character_death_drop(IN p_char_id INT, IN p_x FLOAT, IN p_y FLOAT, IN p_z FLOAT,
  IN p_interior TINYINT, IN p_dimension INT, IN p_ring LONGTEXT, IN p_clothes LONGTEXT)
BEGIN
  DECLARE v_n INT DEFAULT 0;
  DECLARE v_inv INT DEFAULT NULL;
  DECLARE v_skin SMALLINT DEFAULT NULL;
  DECLARE v_clothes INT DEFAULT NULL;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  SELECT inventory_container_id, skin INTO v_inv, v_skin FROM characters WHERE id = p_char_id FOR UPDATE;
  CALL character_drop_items(p_char_id, v_inv, p_ring, p_interior, p_dimension, v_n);
  -- upstream death.pwn: the body leaves a Clothes item holding its skin, 1 m along sin/cos(90); p_clothes is that
  -- spot as one ring entry (MTA toJSON of [x, y, z, nx, ny]), at a random heading like the rest
  IF v_skin IS NOT NULL THEN
    INSERT INTO items (type_uname, data, x, y, z, rz, ground_nx, ground_ny, interior, dimension)
      VALUES ('Clothes', JSON_OBJECT('skin', CAST(v_skin AS SIGNED)), JSON_VALUE(p_clothes, '$[0][0]'),
        JSON_VALUE(p_clothes, '$[0][1]'), JSON_VALUE(p_clothes, '$[0][2]'), RAND() * 360,
        JSON_VALUE(p_clothes, '$[0][3]'), JSON_VALUE(p_clothes, '$[0][4]'), p_interior, p_dimension);
    SET v_clothes = LAST_INSERT_ID();
  END IF;
  UPDATE characters SET alive = 0, died_at = NOW(), x = p_x, y = p_y, z = p_z WHERE id = p_char_id;
  COMMIT;
  SELECT 1 AS ok, 'OK' AS code, JSON_OBJECT('dropped', CAST(v_n AS SIGNED), 'clothes_item_id', CAST(v_clothes AS SIGNED)) AS payload;
END
