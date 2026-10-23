-- Spawn skins are upstream's 7 + 7 (character/shared/logic/spawnpoints.lua), the only ones with tuned hat, mask and
-- armour rows. Characters created on the MVP placeholder skins move to a spawn skin of the same gender, spread by id
-- so they do not all look alike. Supporting every human skin is #72.

UPDATE characters
SET skin = ELT(1 + MOD(id, 7), 60, 170, 250, 188, 206, 50, 254)
WHERE skin IN (7, 20, 21, 22, 23);

UPDATE characters
SET skin = ELT(1 + MOD(id, 7), 192, 93, 233, 193, 90, 191, 131)
WHERE skin IN (12, 13, 40, 41, 56, 69);

INSERT INTO schema_migrations (version, name) VALUES (9, 'spawn_skins') ON DUPLICATE KEY UPDATE name = VALUES(name);
