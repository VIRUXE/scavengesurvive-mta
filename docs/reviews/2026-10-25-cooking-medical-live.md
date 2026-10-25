# Cooking and medical live check with one client (smoke steps 32-33), 2026-10-25

Dev server, one connected client (`VIRUXE`), issues #95 (cooking) and #94 (treatment, infection and drugs), driven
over the `dev` resource's rcon: `rcon.ps1 key` / `cmd` / `lua` / `clua` / `screenshot`. The client logged in through
`clua triggerServerEvent("loginRequested", ...)`; the login dialog then stays drawn and was closed with
`clua exports.ui:dialogClose()` (a tooling gotcha: a scripted login bypasses the dialog's own close). Items came from
`item_create` / `item_create_held` over `rcon.ps1 lua`; the inventory was full (6/6), so a Backpack was worn to hold
the medical items.

## Results

| Step | Checked | Result |
| --- | --- | --- |
| 33 a | campfire, Meat on and off, eat, burn-out | **fail, then fixed** (`7d6f662`): **F** with food in hand always ate it (the hud sends `itemUseRequested` for held food), so cooking was unreachable. After the fix: fire effect on the campfire; held Meat + **F** put it on the fire, label `Meat (Uncooked)`, 60 s later `Meat (Cooked)` with data `{"cooked": 1}`; **F** with empty hands took it off; eaten away from the fire: food 38 -> 100; the campfire burnt out on time into three Burnt Logs |
| 33 b | barbecue fuel, grill, lighting, pick-up | pass: `Needs fuel from a Petrol Can`; `1L of petrol added / 10 BBQ uses`; Meat on grill spot 1; lit: two burner fire effects; 30 s later cooked, fuel 10 -> 9; **F** took the Meat, a second **F** picked the barbecue up with the grill cleared and the fuel kept |
| 33 c | restart mid-cook | checked with DB rows earlier, not on screen |
| 33 d | Petrol Can amount | pass: the can's row read `[{"amount":19.4}]` after the 5 s flush |
| 33 raw | Meat eaten raw | pass: 70 % of its food and `Food Infect` |
| 32 a | labels | pass: `Pills (LSD)`, `Injector (Morphine)`, `Doctor's Bag (2/3, Painkill)`, `Pills (Painkiller)`, `Pills (Antibiotics)`, `Dirty Bandage`. Pill data says `Painkiller`, the drug is `Painkill` |
| 32 b | bandage | pass: bleed 0.497 -> 0.376, chat `Reduced bleedrate from 0.497379 to 0.375576`; the wound infection rolled |
| 32 c | wounds | not driven |
| 32 d | painkiller | pass: +10 hp, `Painkill` listed |
| 32 e | LSD | pass: 22:03 with the drug sky; the 300 s wear-off not watched |
| 32 f | food infection | pass: raw Meat -> `Food Infect`; Antibiotics cured it, the wound infection stayed |
| 32 g | persistence | pass: after `rr character` the wound infection and Antibiotic / Painkill / Lsd still active, the LSD sky back |
| 32 h | treating another player | needs two clients |

Treatment holds cannot be driven from rcon: the client polls the real **F** key every 100 ms and cancels the hold,
so step 32's outcomes went through `exports.character:treatPlayer(p, p, uname, data)`.

## Fixed on the way

- `7d6f662`: held food at a cooker. The nearest Campfire / Barbecue within reach now wins over eating, and empty
  hands at a campfire take the food lying on it (it shares the fire's x/y, so the fire was found first).
- `fc6acd8`: `item_create_held` made bags and safeboxes without a `containers` row (e.g. a crafted ParaBag); fixed
  live in the DB and the schema dumped.
- `12cd152`: the Health Status panel dropped rows past its footer (`Lsd` was missing); it now grows to fit.

## Also seen

- The `NN% Unconscious` footer read 100 % with 2 wounds and bleed 0.37: upstream's formula, capped, not a bug.
- Decided after the run (not live-checked yet): only uncooked food that can be cooked goes onto a campfire or
  barbecue within reach, with the HUD hint `F Cook` instead of `F Eat`; cooked food and food that cannot be cooked
  is eaten even next to a fire (upstream's campfire took any food).

## Still open

The **F**-hold UX by hand (bars, release cancels), 32 c, 32 e wear-off, 32 h (two clients), 33 c on screen, and the
`F Cook` change above. Filed as follow-up issues (see #95 / #94 comments).
