-- ground_nx / ground_ny (the slope an item lies on, set by character_drop_items) belong to one resting place: an
-- update that moves the item without setting new ones (a pickup, item_drop, a container) makes it flat again.
CREATE OR REPLACE TRIGGER items_ground_reset BEFORE UPDATE ON items FOR EACH ROW
BEGIN
  IF NOT (OLD.x <=> NEW.x AND OLD.y <=> NEW.y AND OLD.z <=> NEW.z)
    AND OLD.ground_nx <=> NEW.ground_nx AND OLD.ground_ny <=> NEW.ground_ny THEN
    SET NEW.ground_nx = NULL, NEW.ground_ny = NULL;
  END IF;
END
