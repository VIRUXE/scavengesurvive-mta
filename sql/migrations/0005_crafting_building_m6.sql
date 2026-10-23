-- Milestone M6: Crafting, Building, Apparel
-- Schema already supports holder_kind ('held','holster','bag','hat','mask','armour')
-- and containers.kind ('inventory','bag','safebox','tent','vehicle','supply').

INSERT INTO schema_migrations (version, name) VALUES (5, 'crafting_building_m6') ON DUPLICATE KEY UPDATE name = VALUES(name);
