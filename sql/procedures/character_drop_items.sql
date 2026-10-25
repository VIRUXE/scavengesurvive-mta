CREATE OR REPLACE PROCEDURE character_drop_items(IN p_char_id INT, IN p_inv INT, IN p_x FLOAT, IN p_y FLOAT,
  IN p_z FLOAT, IN p_interior TINYINT, IN p_dimension INT, OUT p_n INT)
BEGIN
  -- Puts everything the character holds or wears, and its inventory, on the ground in a 1.5 m ring around the
  -- point (a bag keeps its contents). Runs inside the caller's transaction: character_death_drop, character_drop_all.
  DECLARE v_done INT DEFAULT 0;
  DECLARE v_id INT;
  DECLARE v_ang FLOAT;
  DECLARE cur CURSOR FOR
    SELECT id FROM items WHERE holder_char_id = p_char_id OR container_id = p_inv ORDER BY id FOR UPDATE;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;
  SET p_n = 0;
  OPEN cur;
  drop_loop: LOOP
    FETCH cur INTO v_id;
    IF v_done = 1 THEN
      LEAVE drop_loop;
    END IF;
    SET v_ang = RADIANS(p_n * 40);
    UPDATE items SET holder_char_id = NULL, holder_kind = NULL, container_id = NULL, slot = NULL,
      x = p_x + 1.5 * COS(v_ang), y = p_y + 1.5 * SIN(v_ang), z = p_z, rz = 0, interior = p_interior,
      dimension = p_dimension WHERE id = v_id;
    SET p_n = p_n + 1;
  END LOOP;
  CLOSE cur;
END
