from __future__ import annotations

from pathlib import Path

from .common import SEED_HEADER, write_text

SETTINGS = {
    "player.combat_log_window": "30", "player.login_freeze_time": "8", "player.ping_limit": "400",
    "spawn.bagtype": "Satchel", "spawn.new_blood": "90", "spawn.new_food": "80", "spawn.new_bleed": "0.0001",
    "spawn.new_items": "Knife", "spawn.res_blood": "100", "spawn.res_food": "40", "spawn.res_bleed": "0",
    "spawn.res_items": "AntiSepBandage", "loot.spawn_multiplier": "1.0", "loot.despawn_minutes": "120",
    "loot.roll_batch": "300", "items.sync_radius": "150", "items.pickup_radius": "2.0",
    "vehicles.spawn_chance": "4.0",
    # M7 staff & ops: upstream settings.ini server/whitelist and server/motd; level1.pwn warn (5 warnings = 1 day ban)
    "server.whitelist": "0", "server.motd": "",
    # upstream server/whitelist-auto-toggle and player/auto-ip-login, both off by default (#86)
    "server.whitelist_auto": "0", "player.auto_ip_login": "0",
    # upstream wl_NonWhitelistTime: seconds a player not listed keeps playing after the whitelist turns on (#90)
    "server.whitelist_kick_s": "300",
    # upstream server/rules and server/staff arrays for /rules and /admins, entries separated by "|"
    "server.rules": "", "server.staff": "", "staff.max_warnings": "5", "staff.warn_ban_hours": "24",
    # M8 supply drops and weapon caches (core/world/supply-crate.pwn, weapons-cache.pwn: tick 60 s, cooldown 600 s,
    # cache 1500 s + random 600 s with 4+ players); drop points come back after loot.drop_point_reuse_hours
    "loot.supply_tick_s": "60", "loot.supply_cooldown_s": "600", "loot.cache_interval_s": "1500",
    "loot.cache_jitter_s": "600", "loot.cache_min_players": "4", "loot.drop_point_reuse_hours": "24",
    # M9 scarcity-driven respawn (ADR 0001, #67): carrying capacity = first roll x cap_multiplier (loot: points x
    # items_per_point per zone); every refill_interval_s the deficit refills at refill_rate per hour with a floor of
    # refill_floor of the cap per hour; consumed points cool down for cooldown x (1 +/- jitter); nothing spawns within
    # min_player_distance of a player; vehicles driven leave_radius from their point and untouched abandon_days are removed
    "loot.cap_multiplier": "1.0", "loot.items_per_point": "2.0", "loot.refill_rate": "0.10", "loot.refill_floor": "0.02",
    "loot.cooldown_minutes": "60", "loot.cooldown_jitter": "0.5", "vehicles.cap_multiplier": "1.0",
    "vehicles.refill_rate": "0.10", "vehicles.refill_floor": "0.02", "vehicles.cooldown_hours": "6",
    "vehicles.cooldown_jitter": "0.33", "vehicles.abandon_days": "3", "vehicles.leave_radius": "100",
    "world.min_player_distance": "150", "world.refill_interval_s": "300",
}


def write_settings_seed(out_seed) -> None:
    rows = ",\n".join(f"('{k}','{v}')" for k, v in sorted(SETTINGS.items()))
    write_text(Path(out_seed) / "0003_settings.sql",
               SEED_HEADER + "INSERT INTO settings (skey, svalue) VALUES\n" + rows + "\nON DUPLICATE KEY UPDATE svalue = svalue;\n")
