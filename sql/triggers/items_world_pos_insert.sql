-- world_items_pos mirrors the position of every item lying in the world (x IS NOT NULL) for the spatial index;
-- a SPATIAL key needs NOT NULL, so it cannot be a generated column on items. Deletes follow through its FK.
CREATE OR REPLACE TRIGGER items_world_pos_insert AFTER INSERT ON items FOR EACH ROW
BEGIN
  IF NEW.x IS NOT NULL THEN
    INSERT INTO world_items_pos (item_id, pos) VALUES (NEW.id, POINT(NEW.x, NEW.y));
  END IF;
END
