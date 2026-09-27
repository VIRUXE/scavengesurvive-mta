from __future__ import annotations

from pathlib import Path

from .common import SEED_HEADER, write_text

SETTINGS = {
    "player.combat_log_window": "30", "player.login_freeze_time": "8", "player.ping_limit": "400",
    "spawn.bagtype": "Satchel", "spawn.new_blood": "90", "spawn.new_food": "80", "spawn.new_bleed": "0.0001",
    "spawn.new_items": "Knife", "spawn.res_blood": "100", "spawn.res_food": "40", "spawn.res_bleed": "0",
    "spawn.res_items": "AntiSepBandage", "loot.spawn_multiplier": "1.0", "loot.despawn_minutes": "120",
    "loot.reroll_minutes": "30", "loot.roll_batch": "300", "items.sync_radius": "150", "items.pickup_radius": "2.0",
}


def write_settings_seed(out_seed) -> None:
    rows = ",\n".join(f"('{k}','{v}')" for k, v in sorted(SETTINGS.items()))
    write_text(Path(out_seed) / "0003_settings.sql",
               SEED_HEADER + "INSERT INTO settings (skey, svalue) VALUES\n" + rows + "\nON DUPLICATE KEY UPDATE svalue = svalue;\n")
