CREATE OR REPLACE PROCEDURE item_wear(IN p_item_id INT, IN p_char_id INT, IN p_holder_kind VARCHAR(16))
BEGIN
  DECLARE v_item_char INT DEFAULT NULL;
  DECLARE v_item_kind VARCHAR(16) DEFAULT NULL;
  DECLARE v_item_container INT DEFAULT NULL;
  DECLARE v_item_slot INT DEFAULT NULL;
  DECLARE v_old_id INT DEFAULT NULL;
  DECLARE v_cont_owner INT DEFAULT NULL;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  IF p_holder_kind NOT IN ('hat', 'mask', 'armour', 'holster', 'bag') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid holder_kind for item_wear';
  END IF;

  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;

  SELECT holder_char_id, holder_kind, container_id, slot
    INTO v_item_char, v_item_kind, v_item_container, v_item_slot
    FROM items WHERE id = p_item_id FOR UPDATE;

  IF v_item_char <=> p_char_id THEN
    SET v_cont_owner = p_char_id;
  ELSEIF v_item_container IS NOT NULL THEN
    SELECT owner_char_id INTO v_cont_owner FROM containers WHERE id = v_item_container;
  END IF;

  IF NOT (v_cont_owner <=> p_char_id) THEN
    ROLLBACK;
    SELECT 0 AS ok, 'NOT_OWNER' AS code, NULL AS payload;
  ELSE
    SELECT id INTO v_old_id
      FROM items WHERE holder_char_id = p_char_id AND holder_kind = p_holder_kind FOR UPDATE;

    IF v_old_id IS NOT NULL THEN
      -- Temporarily clear holder_kind to prevent duplicate key collision during swap
      UPDATE items SET holder_kind = NULL WHERE id = v_old_id;
    END IF;

    UPDATE items
      SET holder_char_id = p_char_id, holder_kind = p_holder_kind, container_id = NULL, slot = NULL
      WHERE id = p_item_id;

    IF v_old_id IS NOT NULL THEN
      IF v_item_kind = 'held' THEN
        UPDATE items SET holder_char_id = p_char_id, holder_kind = 'held', container_id = NULL, slot = NULL WHERE id = v_old_id;
      ELSEIF v_item_container IS NOT NULL THEN
        UPDATE items SET holder_char_id = NULL, holder_kind = NULL, container_id = v_item_container, slot = v_item_slot WHERE id = v_old_id;
      ELSE
        UPDATE items SET holder_char_id = p_char_id, holder_kind = 'held', container_id = NULL, slot = NULL WHERE id = v_old_id;
      END IF;
    END IF;

    COMMIT;
    SELECT 1 AS ok, 'OK' AS code,
      JSON_OBJECT(
        'item_id', CAST(p_item_id AS SIGNED),
        'swapped_id', CAST(v_old_id AS SIGNED),
        'slot', p_holder_kind
      ) AS payload;
  END IF;
END;
