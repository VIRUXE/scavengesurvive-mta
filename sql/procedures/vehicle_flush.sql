CREATE OR REPLACE PROCEDURE vehicle_flush(IN p_rows JSON)
BEGIN
  DECLARE v_n INT DEFAULT 0;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  UPDATE vehicles v
    JOIN JSON_TABLE(p_rows, '$[0][*]' COLUMNS (
      id INT PATH '$.id', x FLOAT PATH '$.x', y FLOAT PATH '$.y', z FLOAT PATH '$.z', rz FLOAT PATH '$.rz',
      health FLOAT PATH '$.health', fuel FLOAT PATH '$.fuel', locked TINYINT PATH '$.locked')) j ON j.id = v.id
    SET v.x = j.x, v.y = j.y, v.z = j.z, v.rz = j.rz, v.health = j.health, v.fuel = j.fuel, v.locked = j.locked;
  SET v_n = ROW_COUNT();
  COMMIT;
  SELECT 1 AS ok, 'OK' AS code, JSON_OBJECT('updated', CAST(v_n AS SIGNED)) AS payload;
END
