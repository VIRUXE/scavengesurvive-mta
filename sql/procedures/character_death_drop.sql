CREATE OR REPLACE PROCEDURE character_death_drop(IN p_char_id INT, IN p_x FLOAT, IN p_y FLOAT, IN p_z FLOAT,
  IN p_interior TINYINT, IN p_dimension INT)
BEGIN
  DECLARE v_done INT DEFAULT 0;
  DECLARE v_id INT;
  DECLARE v_n INT DEFAULT 0;
  DECLARE v_ang FLOAT;
  DECLARE v_x FLOAT;
  DECLARE v_y FLOAT;
  DECLARE v_inv INT DEFAULT NULL;
  DECLARE v_skin SMALLINT DEFAULT NULL;
  DECLARE v_clothes INT DEFAULT NULL;
  DECLARE cur CURSOR FOR
    SELECT id FROM items WHERE holder_char_id = p_char_id OR container_id = v_inv ORDER BY id FOR UPDATE;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  SELECT inventory_container_id, skin INTO v_inv, v_skin FROM characters WHERE id = p_char_id FOR UPDATE;
  OPEN cur;
  drop_loop: LOOP
    FETCH cur INTO v_id;
    IF v_done = 1 THEN
      LEAVE drop_loop;
    END IF;
    SET v_ang = RADIANS(v_n * 40);
    SET v_x = p_x + 1.5 * COS(v_ang);
    SET v_y = p_y + 1.5 * SIN(v_ang);
    UPDATE items SET holder_char_id = NULL, holder_kind = NULL, container_id = NULL, slot = NULL,
      x = v_x, y = v_y, z = p_z, rz = 0, interior = p_interior, dimension = p_dimension WHERE id = v_id;
    INSERT INTO world_items_pos (item_id, pos) VALUES (v_id, POINT(v_x, v_y));
    SET v_n = v_n + 1;
  END LOOP;
  CLOSE cur;
  -- upstream death.pwn: the body leaves a Clothes item holding its skin, 1 m along sin/cos(90)
  IF v_skin IS NOT NULL THEN
    INSERT INTO items (type_uname, data, x, y, z, rz, interior, dimension)
      VALUES ('Clothes', JSON_OBJECT('skin', CAST(v_skin AS SIGNED)), p_x + 1.0, p_y, p_z, 0, p_interior, p_dimension);
    SET v_clothes = LAST_INSERT_ID();
    INSERT INTO world_items_pos (item_id, pos) VALUES (v_clothes, POINT(p_x + 1.0, p_y));
  END IF;
  UPDATE characters SET alive = 0, died_at = NOW(), x = p_x, y = p_y, z = p_z WHERE id = p_char_id;
  COMMIT;
  SELECT 1 AS ok, 'OK' AS code, JSON_OBJECT('dropped', CAST(v_n AS SIGNED), 'clothes_item_id', CAST(v_clothes AS SIGNED)) AS payload;
END
