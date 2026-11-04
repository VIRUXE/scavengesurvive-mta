# Placeholders: shots, renders and films still to be made

Every green slate on the website and every `<!-- shot:<id> -->` marker in the wiki carries one of the ids below. The
site reads `site/data/placeholders.json`; to fill a slot, drop the file under `site/assets/img/shots/` (or `renders/`),
set that entry's `file` (and `caption`), and the slate becomes the image on the next deploy. For a film, `file` is the
YouTube video id and `poster` a still. The wiki markers are replaced by hand with an image line once the file is in
the wiki's `images/screens/`.

Screenshots come from the dev server over rcon (`pwsh server-config/rcon.ps1 screenshot <player> 1920 1080`; the chat
box is omitted) or, for anything with a ped alone, from the studio (`docs/dev-studio.md`). Renders use the Blender
pipeline in `tools/` (`render_scenes.py`, `render_places.py`, `render_item_models.py`; the scene recipe lives in
`docs/images/scenes/index.json`). Deliver 1920×1080 or wider; `python -m tools.site_assets` makes the WebP copies.

## In-game screenshots (`shot-*`)

| id | What to capture | How | Used on |
| --- | --- | --- | --- |
| `shot-hero-gameplay` | Third-person fight at dusk near a fort wall, tracers visible, HUD on, no chat box | rcon screenshot, two clients, `setTime` to dusk | index gallery, wiki HUD |
| `shot-inventory` | The `H` inventory: body preview, six gear tiles with their 3D previews, a bag and a pistol equipped | rcon `key <player> inventory` then screenshot | index gallery, wiki Inventory |
| `shot-dashboard` | Driver's dashboard with BAT and FUEL lit, engine running, night, headlights on | `exports.hud:dashboardPreview` over `clua` | index driving, wiki Drivers Dashboard |
| `shot-keypad` | The 12-key dx keypad on a Metal Door, one digit entered | build a door with keypad, press `F` | wiki Keypads |
| `shot-radio-panel` | The dx radio panel open, a frequency set, radio in hand | `additem Radio`, open the panel | wiki Radio |
| `shot-death-screen` | The death screen over the body and its ring of dropped items | kill a loaded character | wiki Death |
| `shot-supply-drop-live` | A supply crate descending under its parachute with smoke, players running in | `/drop` as staff, screenshot mid-descent | wiki Supply Drops |
| `shot-weather-night` | Rain at night in San Fierro, a lit campfire in the frame | `setWeather 8`, night | wiki World & Zones |
| `shot-house-interior` | Inside a hollow town house: glazed window, fitted door open, loot on the floor | `/house` tour | wiki Houses & Trailers |
| `shot-welding` | Welding a Metal Panel onto the Airstream, Generator beside it, sparks | runbook `welding-carmour.md` | index driving (optional), wiki Vehicle Armour |
| `shot-bobcat-salvage` | A Bobcat with its tailgate and a door off, the parts on the ground, Wrench in hand | runbook `bobcat-parts.md` | index driving, wiki Bobcat Salvage Parts |
| `shot-voice-indicator` | Two players talking: the HUD voice marker and the centre-left names | two clients with voice | wiki Voice |
| `shot-staff-panel` | The staff panel on `P` with the player list, a report open | staff account | wiki Reports & Bans |
| `shot-crafting-window` | The Workbench crafting window with a recipe selected and its ingredients listed | at a fixed Workbench | wiki Workbench |
| `shot-trailer-tow` | A Bobcat towing the Airstream on the Fort Carson road, golden hour | place Airstream, hitch, `setTime 18` | wiki Trailers & Towing |
| `shot-campfire-cooking` | Cooking raw meat on a campfire at night, the hold bar visible | `additem Campfire`, `RawMeat` | wiki Campfire & BBQ |
| `shot-combat-tracers` | Three tracers crossing a street at night, muzzle flash visible | two clients, night | index gallery, wiki Firearms |
| `shot-login-language` | The first-login language window with the ten languages | fresh account | wiki Languages |
| `shot-chat-radio` | Local, global and radio lines in the chat box, the radio panel open | two clients | wiki Chat |

## Blender renders (`render-*`)

| id | What to render | Notes | Used on |
| --- | --- | --- | --- |
| `render-hero-key-art` | Wide key art for the hero: a survivor at a fort gate at dusk | 2560×1440, cycles, golden light; replaces the sandstorm shot when ready | index hero |
| `render-feature-objective` | Two survivors on a rooftop looking over Los Santos | 1600×900, dusk; slate background | index slates |
| `render-feature-survival` | A campfire with food and a bandage | 1600×900, night | index slates |
| `render-feature-building` | A fort wall with a keypad door and a plot pole | 1600×900, overcast | index slates |
| `render-feature-combat` | An M4 with magazines and rounds on a crate | 1600×900, day | index slates |
| `render-feature-crafting` | The Workbench mid-recipe with scrap and tools | 1600×900, golden | index slates |
| `render-feature-driving` | A Bobcat with the bonnet open, battery and starter on the ground | 1600×900, day | index slates |
| `render-hatless-twins-row` | The 22 hatless twins in a row, bare heads | 2400×600, studio light | media, wiki Clothes & Hats |
| `render-stove-lit` | The camper stove with all four burners lit, close | 1600×900, night | media |
| `render-airstream-armoured` | The Airstream fully armoured with welded panels, three-quarter view | 1600×900 | media, wiki Vehicle Armour |
| `render-bobcat-parts-exploded` | Exploded view of the twelve Bobcat parts around the truck | 1600×900 | media, wiki Bobcat Salvage Parts |
| `render-hats-row` | The nine cut hats floating in a row | 2400×500, studio light | media |

## Films (`video-*`)

| id | What | Length |
| --- | --- | --- |
| `video-trailer` | Wake on the beach, loot, build, fight, die | 60 s, 1080p60 |
| `video-first-hour` | Your first hour, narrated: register, the HUD, picking up, bandaging, the first vehicle | 3 to 5 min |
| `video-driving` | Refuel, flat battery, starter swap, salvage parts, towing the Airstream | 2 to 3 min |

The slates on the index page currently use existing renders where one fits (the six feature slates sit on
`townhouse-street`, `camp`, `doorway`, `arsenal`, `workbench` and `airstream`); the `render-feature-*` ids are the
upgrade path, not a gap.
