CREATE OR REPLACE PROCEDURE character_create(
  IN p_account_id INT, IN p_skin SMALLINT, IN p_x FLOAT, IN p_y FLOAT, IN p_z FLOAT, IN p_rz FLOAT,
  IN p_hp FLOAT, IN p_food FLOAT, IN p_bleed FLOAT)
BEGIN
  DECLARE v_char INT;
  DECLARE v_cont INT;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  UPDATE characters SET alive = 0, died_at = IFNULL(died_at, NOW()) WHERE account_id = p_account_id AND alive = 1;
  INSERT INTO characters (account_id, skin, hp, food, bleed, x, y, z, rz)
    VALUES (p_account_id, p_skin, p_hp, p_food, p_bleed, p_x, p_y, p_z, p_rz);
  SET v_char = LAST_INSERT_ID();
  INSERT INTO containers (kind, size, owner_char_id) VALUES ('inventory', 6, v_char);
  SET v_cont = LAST_INSERT_ID();
  UPDATE characters SET inventory_container_id = v_cont WHERE id = v_char;
  COMMIT;
  SELECT 1 AS ok, 'OK' AS code, JSON_OBJECT('character_id', CAST(v_char AS SIGNED), 'inventory_container_id', CAST(v_cont AS SIGNED)) AS payload;
END
