-- Derived from Southclaws/ScavengeSurvive (MPL-2.0). See THIRD_PARTY_NOTICES.md
-- GENERATED FILE - do not edit; run: python -m tools.convert all
INSERT INTO settings (skey, svalue) VALUES
('items.pickup_radius','2.0'),
('items.sync_radius','150'),
('loot.despawn_minutes','120'),
('loot.reroll_minutes','30'),
('loot.roll_batch','300'),
('loot.spawn_multiplier','1.0'),
('player.combat_log_window','30'),
('player.login_freeze_time','8'),
('player.ping_limit','400'),
('spawn.bagtype','Satchel'),
('spawn.new_bleed','0.0001'),
('spawn.new_blood','90'),
('spawn.new_food','80'),
('spawn.new_items','Knife'),
('spawn.res_bleed','0'),
('spawn.res_blood','100'),
('spawn.res_food','40'),
('spawn.res_items','AntiSepBandage')
ON DUPLICATE KEY UPDATE svalue = svalue;
