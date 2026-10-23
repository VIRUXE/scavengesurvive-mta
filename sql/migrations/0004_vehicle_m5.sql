ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS key_code INT NULL DEFAULT NULL AFTER locked;

ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS trailer_id INT NULL DEFAULT NULL AFTER key_code;

ALTER TABLE vehicles ADD CONSTRAINT fk_vehicles_trailer FOREIGN KEY (trailer_id) REFERENCES vehicles(id) ON DELETE SET NULL;

ALTER TABLE containers ADD COLUMN IF NOT EXISTS owner_vehicle_id INT NULL AFTER owner_item_id;

ALTER TABLE containers ADD CONSTRAINT uq_containers_owner_vehicle UNIQUE (owner_vehicle_id);

ALTER TABLE containers ADD CONSTRAINT fk_containers_owner_vehicle FOREIGN KEY (owner_vehicle_id) REFERENCES vehicles(id) ON DELETE CASCADE;

INSERT INTO schema_migrations (version, name) VALUES (4, 'vehicle_m5') ON DUPLICATE KEY UPDATE name = VALUES(name);
