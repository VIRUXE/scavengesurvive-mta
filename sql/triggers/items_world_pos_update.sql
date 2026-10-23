-- An item entering, moving in or leaving the world updates its world_items_pos row; other updates cost one compare.
CREATE OR REPLACE TRIGGER items_world_pos_update AFTER UPDATE ON items FOR EACH ROW
BEGIN
  IF NEW.x IS NULL THEN
    IF OLD.x IS NOT NULL THEN
      DELETE FROM world_items_pos WHERE item_id = NEW.id;
    END IF;
  ELSEIF NOT (OLD.x <=> NEW.x AND OLD.y <=> NEW.y) THEN
    INSERT INTO world_items_pos (item_id, pos) VALUES (NEW.id, POINT(NEW.x, NEW.y))
      ON DUPLICATE KEY UPDATE pos = VALUE(pos);
  END IF;
END
