CREATE OR REPLACE PROCEDURE character_drop_items(IN p_char_id INT, IN p_inv INT, IN p_ring LONGTEXT,
  IN p_interior TINYINT, IN p_dimension INT, OUT p_n INT)
BEGIN
  -- Puts everything the character holds or wears, and its inventory, on the ground (a bag keeps its contents):
  -- item n goes to spot n mod the ring's length. p_ring is MTA's toJSON of [[x, y, z, rz], ...] from character
  -- drop.lua, z measured by the client; toJSON's outer [ ] is why the paths start at '$[0]'.
  -- Runs inside the caller's transaction: character_death_drop, character_drop_all.
  DECLARE v_done INT DEFAULT 0;
  DECLARE v_id INT;
  DECLARE v_slot VARCHAR(16);
  DECLARE v_len INT DEFAULT JSON_LENGTH(p_ring, '$[0]');
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
    SET v_slot = CONCAT('$[0][', p_n MOD v_len, ']');
    UPDATE items SET holder_char_id = NULL, holder_kind = NULL, container_id = NULL, slot = NULL,
      x = JSON_VALUE(p_ring, CONCAT(v_slot, '[0]')), y = JSON_VALUE(p_ring, CONCAT(v_slot, '[1]')),
      z = JSON_VALUE(p_ring, CONCAT(v_slot, '[2]')), rz = JSON_VALUE(p_ring, CONCAT(v_slot, '[3]')),
      interior = p_interior, dimension = p_dimension
      WHERE id = v_id;
    SET p_n = p_n + 1;
  END LOOP;
  CLOSE cur;
END
