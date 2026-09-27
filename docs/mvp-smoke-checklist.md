# MVP smoke checklist (two clients, local server)

Setup: `pwsh server-config/run-local.ps1 -Reset`. Client A and client B connect to `127.0.0.1:22003`.
On one PC, start the second client with MTA's multiple-instance option, or use a second machine on the LAN.
The two clients need different MTA nicknames: the account name is the nickname, and one account allows one session.
Record pass/fail and the date. **Any failing step becomes a fix in the task that owns the resource** (lib 4, data 5,
ui 6, auth 7, character 8, items 9, loot 10, hud 11, weapons 12, dev/config 13), with a regression test where one fits.

1. **Boot.** `logs/server.log` shows `Resources: N loaded, 0 failed` and `Server started and is ready to accept
   connections!` with no `ERROR` or `Access denied` line (MTA does not log each resource it starts at boot).
   `rg -n "ERROR" "…/mods/deathmatch/logs/scripts.log"` returns nothing. `mariadb -u root -e "SELECT COUNT(*) FROM
   information_schema.processlist WHERE db='scavengesurvive'"` shows 5 (auth, character, items, loot, dev).
2. **Account.** A registers, logs in and spawns on the shoreline. The HUD shows hp/food bars, and **H** lists a Knife.
   Relog and log in again with the same password.
3. **DB round trip.** A: `/dbtest` prints `dbtest: <n> ms ok=false code=UNKNOWN_TYPE` with n < 50.
4. **Pick up / drop.** A: `/additem Wrench`. Within 2 s a "Wrench" label appears at the item. **F** picks it up
   (held name on the HUD), **N** drops it at your feet, **F** picks it up again. B sees each change.
5. **Inventory.** A: **Y** puts the Wrench away. **H** lists it, and **Take** puts it back in hand. Repeat `/additem` +
   **Y** until the toast says "No space". The item that does not fit stays in hand.
6. **Bag.** A: `/additem Satchel`, **F**, **Y**: the satchel is worn (visible on the back for B). Put more items away
   than the inventory holds. They overflow into the bag, and **H** shows both lists. A second satchel, **F**, **Y**:
   the toast says "You already wear a bag", and `scripts.log` has no new `ERROR`.
7. **Food.** A: `/additem HotDog`, **F**, **H** → **Eat** on the `[hand]` row. `/stats` food goes up, the item is
   consumed and the `[hand]` row disappears. `/additem HotDog`, **Y**, **H** → **Eat** on its inventory row works too.
8. **Starvation death.** A: `/setfood 0`, `/sethp 3`. Within seconds the death screen shows the cause. **Play Again**
   spawns a new character (`/stats` hp=100 food=40) with an AntiSepBandage in **H**. B walks to the corpse spot
   and sees A's old items on the ground.
9. **PvP.** A: `/additem M9Pistol`, **F**, shoots B. B gets a toast, a bleed bar appears on B's HUD, and B's hp drains
   (`/stats` on B). B reconnects while bleeding: the bleed bar is still there. Keep shooting: B dies, and B's items
   drop where B died.
10. **Loot.** A goes to Los Santos (e.g. Grove Street) and runs `/rollloot`. Items appear at upstream spawn points
    (labels within ~2 s). Run ~500 m away: the objects unload. Come back: they reload with the same ids.
11. **Restarts.** A holds an item. Server console `rr items`: the item is still in A's hand, and world items reappear
    with no duplicates. `rr character`: `/stats` is unchanged (±1 tick). `rr auth`: the login window reappears on
   both clients. Then `shutdown` and
    `pwsh server-config/run-local.ps1` (no `-Reset`). A logs in with the same character, position, stats and inventory.
