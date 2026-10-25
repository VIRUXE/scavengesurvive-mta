CREATE OR REPLACE PROCEDURE character_drop_all(IN p_char_id INT, IN p_x FLOAT, IN p_y FLOAT, IN p_z FLOAT,
  IN p_interior TINYINT, IN p_dimension INT)
BEGIN
  -- /dropall (upstream commands.pwn DropItems(death = false)): the death drop without dying, no Clothes item.
  DECLARE v_n INT DEFAULT 0;
  DECLARE v_inv INT DEFAULT NULL;
  DECLARE v_alive TINYINT DEFAULT NULL;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  SELECT inventory_container_id, alive INTO v_inv, v_alive FROM characters WHERE id = p_char_id FOR UPDATE;
  IF v_alive IS NULL OR v_alive = 0 THEN
    ROLLBACK;
    SELECT 0 AS ok, 'NOT_ALIVE' AS code, NULL AS payload;
  ELSE
    CALL character_drop_items(p_char_id, v_inv, p_x, p_y, p_z, p_interior, p_dimension, v_n);
    COMMIT;
    SELECT 1 AS ok, 'OK' AS code, JSON_OBJECT('dropped', CAST(v_n AS SIGNED)) AS payload;
  END IF;
END
