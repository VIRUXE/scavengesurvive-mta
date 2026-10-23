CREATE OR REPLACE PROCEDURE item_unwear(IN p_char_id INT, IN p_holder_kind VARCHAR(16))
BEGIN
  DECLARE v_item_id INT DEFAULT NULL;
  DECLARE v_held INT DEFAULT 0;
  DECLARE v_inv INT DEFAULT NULL;
  DECLARE v_free_slot INT DEFAULT NULL;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  IF p_holder_kind NOT IN ('hat', 'mask', 'armour', 'holster', 'bag') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid holder_kind for item_unwear';
  END IF;

  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;

  SELECT id INTO v_item_id
    FROM items WHERE holder_char_id = p_char_id AND holder_kind = p_holder_kind FOR UPDATE;

  IF v_item_id IS NULL THEN
    ROLLBACK;
    SELECT 0 AS ok, 'NOT_WORN' AS code, NULL AS payload;
  ELSE
    SELECT COUNT(*) INTO v_held
      FROM items WHERE holder_char_id = p_char_id AND holder_kind = 'held';

    IF v_held = 0 THEN
      UPDATE items
        SET holder_char_id = p_char_id, holder_kind = 'held', container_id = NULL, slot = NULL
        WHERE id = v_item_id;
      COMMIT;
      SELECT 1 AS ok, 'OK' AS code,
        JSON_OBJECT(
          'item_id', CAST(v_item_id AS SIGNED),
          'destination', 'held',
          'slot', p_holder_kind
        ) AS payload;
    ELSE
      SELECT inventory_container_id INTO v_inv FROM characters WHERE id = p_char_id;

      SELECT s.n INTO v_free_slot
      FROM (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5) s
      WHERE s.n NOT IN (SELECT slot FROM items WHERE container_id = v_inv AND slot IS NOT NULL)
      ORDER BY s.n LIMIT 1;

      IF v_free_slot IS NOT NULL THEN
        UPDATE items
          SET holder_char_id = NULL, holder_kind = NULL, container_id = v_inv, slot = v_free_slot
          WHERE id = v_item_id;
        COMMIT;
        SELECT 1 AS ok, 'OK' AS code,
          JSON_OBJECT(
            'item_id', CAST(v_item_id AS SIGNED),
            'destination', 'inventory',
            'slot', CAST(v_free_slot AS SIGNED),
            'wear_slot', p_holder_kind
          ) AS payload;
      ELSE
        ROLLBACK;
        SELECT 0 AS ok, 'INVENTORY_FULL' AS code, NULL AS payload;
      END IF;
    END IF;
  END IF;
END;
