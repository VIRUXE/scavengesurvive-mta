from __future__ import annotations

from pathlib import Path

from .common import SEED_HEADER, write_text

SETTINGS = {
    "player.combat_log_window": "30", "player.login_freeze_time": "8", "player.ping_limit": "400",
    "spawn.bagtype": "Satchel", "spawn.new_blood": "90", "spawn.new_food": "80", "spawn.new_bleed": "0.0001",
    "spawn.new_items": "Knife", "spawn.res_blood": "100", "spawn.res_food": "40", "spawn.res_bleed": "0",
    "spawn.res_items": "AntiSepBandage", "loot.spawn_multiplier": "1.0", "loot.despawn_minutes": "120",
    "loot.reroll_minutes": "30", "loot.roll_batch": "300", "items.sync_radius": "150", "items.pickup_radius": "2.0",
    "vehicles.spawn_chance": "4.0",
    # M7 staff & ops: upstream settings.ini server/whitelist and server/motd; level1.pwn warn (5 warnings = 1 day ban)
    "server.whitelist": "0", "server.motd": "", "staff.max_warnings": "5", "staff.warn_ban_hours": "24",
    # M8 supply drops and weapon caches (core/world/supply-crate.pwn, weapons-cache.pwn: tick 60 s, cooldown 600 s,
    # cache 1500 s + random 600 s with 4+ players); drop points come back after loot.drop_point_reuse_hours
    "loot.supply_tick_s": "60", "loot.supply_cooldown_s": "600", "loot.cache_interval_s": "1500",
    "loot.cache_jitter_s": "600", "loot.cache_min_players": "4", "loot.drop_point_reuse_hours": "24",
}


def write_settings_seed(out_seed) -> None:
    rows = ",\n".join(f"('{k}','{v}')" for k, v in sorted(SETTINGS.items()))
    write_text(Path(out_seed) / "0003_settings.sql",
               SEED_HEADER + "INSERT INTO settings (skey, svalue) VALUES\n" + rows + "\nON DUPLICATE KEY UPDATE svalue = svalue;\n")
