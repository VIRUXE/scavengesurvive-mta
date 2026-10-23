CREATE OR REPLACE PROCEDURE item_data_flush(IN p_rows JSON)
BEGIN
  -- p_rows: MTA's toJSON of [{id, data = JSON text}] (wrapped in an outer array): the held items whose data changed
  DECLARE v_n INT DEFAULT 0;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  UPDATE items i
    JOIN JSON_TABLE(p_rows, '$[0][*]' COLUMNS (id INT PATH '$.id', data LONGTEXT PATH '$.data')) j ON j.id = i.id
    SET i.data = j.data;
  SET v_n = ROW_COUNT();
  COMMIT;
  SELECT 1 AS ok, 'OK' AS code, JSON_OBJECT('updated', CAST(v_n AS SIGNED)) AS payload;
END
