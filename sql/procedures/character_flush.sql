CREATE OR REPLACE PROCEDURE character_flush(IN p_rows JSON)
BEGIN
  DECLARE v_n INT DEFAULT 0;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  UPDATE characters c
    JOIN JSON_TABLE(p_rows, '$[0][*]' COLUMNS (
      id INT PATH '$.id', hp FLOAT PATH '$.hp', food FLOAT PATH '$.food', bleed FLOAT PATH '$.bleed',
      x FLOAT PATH '$.x', y FLOAT PATH '$.y', z FLOAT PATH '$.z', rz FLOAT PATH '$.rz',
      interior INT PATH '$.interior', dimension INT PATH '$.dimension')) j ON j.id = c.id
    SET c.hp = j.hp, c.food = j.food, c.bleed = j.bleed, c.x = j.x, c.y = j.y, c.z = j.z, c.rz = j.rz,
      c.interior = IFNULL(j.interior, c.interior), c.dimension = IFNULL(j.dimension, c.dimension)
    WHERE c.alive = 1;
  SET v_n = ROW_COUNT();
  COMMIT;
  SELECT 1 AS ok, 'OK' AS code, JSON_OBJECT('updated', CAST(v_n AS SIGNED)) AS payload;
END
