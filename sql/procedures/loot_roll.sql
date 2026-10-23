CREATE OR REPLACE PROCEDURE loot_roll(IN p_rolls JSON, IN p_despawn_minutes INT)
BEGIN
  -- p_rolls: MTA's toJSON of [{s = spawn id, cd = cooldown seconds, items = [{u, data (JSON text or nil), x, y, z, rz}]}],
  -- wrapped in an outer array; one transaction places every item (bags get their container, the trigger the
  -- world position), spends each zone's allowance and cools every point.
  DECLARE v_n INT DEFAULT 0;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  INSERT INTO items (type_uname, hitpoints, data, x, y, z, rz, interior, dimension, loot_spawn_id, loot_zone, despawn_at)
    SELECT j.u, 5, j.data, j.x, j.y, j.z, j.rz, s.interior, s.dimension, s.id, s.zone, NOW() + INTERVAL p_despawn_minutes MINUTE
    FROM JSON_TABLE(p_rolls, '$[0][*]' COLUMNS (sid INT PATH '$.s', NESTED PATH '$.items[*]' COLUMNS (
      u VARCHAR(32) PATH '$.u', data LONGTEXT PATH '$.data', x FLOAT PATH '$.x', y FLOAT PATH '$.y', z FLOAT PATH '$.z',
      rz FLOAT PATH '$.rz'))) j
    JOIN loot_spawns s ON s.id = j.sid
    JOIN item_types t ON t.uname = j.u;
  SET v_n = ROW_COUNT();
  INSERT INTO containers (kind, size, owner_item_id)
    SELECT t.category, IFNULL(t.container_size, 8), i.id
    FROM JSON_TABLE(p_rolls, '$[0][*]' COLUMNS (sid INT PATH '$.s')) j
    JOIN items i ON i.loot_spawn_id = j.sid
    JOIN item_types t ON t.uname = i.type_uname
    WHERE t.category IN ('bag', 'safebox') AND NOT EXISTS (SELECT 1 FROM containers c WHERE c.owner_item_id = i.id);
  UPDATE world_budget b
    JOIN (SELECT s.zone, COUNT(*) AS n
          FROM JSON_TABLE(p_rolls, '$[0][*]' COLUMNS (sid INT PATH '$.s', NESTED PATH '$.items[*]' COLUMNS (
            u VARCHAR(32) PATH '$.u'))) j
          JOIN loot_spawns s ON s.id = j.sid JOIN item_types t ON t.uname = j.u GROUP BY s.zone) z ON z.zone = b.zone
    SET b.allowance = GREATEST(b.allowance - z.n, 0)
    WHERE b.category = 'loot';
  UPDATE loot_spawn_state st
    JOIN JSON_TABLE(p_rolls, '$[0][*]' COLUMNS (sid INT PATH '$.s', cd INT PATH '$.cd')) j ON j.sid = st.spawn_id
    SET st.next_roll_at = NOW() + INTERVAL j.cd SECOND;
  COMMIT;
  SELECT 1 AS ok, 'OK' AS code, JSON_OBJECT('created', CAST(v_n AS SIGNED)) AS payload;
END
