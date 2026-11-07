# Driver's Dashboard

While you drive a vehicle with an engine and a fuel tank, an instrument cluster sits at the bottom centre of the screen: a dark binnacle holding a speedometer and a rev counter, a fuel gauge and a voltmeter between them, a row of warning lamps under those, and the ignition switch beside it. It is lit from the state of the vehicle you sit in and plays out what happens when you turn the key, so each way a start can fail looks different. Only the driver sees it. The bottom right corner ([HUD](HUD)) shows only the vehicle's name; damage shows on the car itself, as engine smoke and dents.

<!-- shot:shot-dashboard -->

## The dials

- **Speedometer** (left): km/h over a 240 degree scale, numbered every 20 km/h (every 40 on faster vehicles). The scale's end follows the vehicle's top speed, from 120 up to 320 km/h. A green digital readout under the needle shows the speed in figures.
- **Rev counter** (right): 0 to 7 thousand rpm, red from about 6,000. The needle follows your speed within the current gear, climbing through each gear and dropping back at the shift; standing still with the throttle pressed it rises a little. It lags behind the engine and falls faster than it climbs. With the engine off it rests at zero.
- **Fuel gauge** (centre left): `E` to `F`, red at the bottom eighth. The needle settles over about a second, like a damped gauge.
- **Voltmeter** (centre right): 8 to 16 V, red under 10.5 V. It shows 14.1 V while the engine runs and charges the battery. With the engine off it reads the battery's resting voltage, 11.6 V empty to 12.7 V full, and it sags while the starter turns. Vehicles without a battery (motorbikes, boats, the open vehicles without doors) read as if theirs were always full.

The markings are lit by the backlight: dark grey until the key is turned to ACC or the engine runs, dimmer in ACC and bright while the engine runs. With the panel dark every needle rests at its stop. With no battery under the bonnet the cluster is dead.

## The lamps

Left to right under the small gauges, each a symbol as on a real dashboard. A lamp is dark grey until it lights.

| Lamp | Colour | Lit when |
|:--|:--|:--|
| battery | red | the charge lamp: the alternator is not charging while the engine runs |
| engine | amber | the vehicle is worn (650 health or less); red when it is wrecked (300 or less) |
| fuel pump | amber | the tank is at 15 % or less; red at 5 % or less or empty |
| headlamp | green | the headlights are on |
| door | green / red | always lit: green when the doors are unlocked, red when they are locked |

The thresholds are the ones that matter when you drive: under 450 health the engine can cut out at speed, at 300 or less it will not start, under 10 % the battery will not turn it over. See [Vehicles](Vehicles), [Fuel](Fuel) and [Car Batteries & Starters](Car-Batteries-and-Starters).

## The ignition switch

A chrome barrel sits just left of the binnacle. Three ticks sit around it, `OFF`, `ACC` and `START` from left round to right, as on a real barrel, and the key turns to the one it is in; the lit tick is grey, amber or red to match. The key goes to `START` while the starter turns, then springs back to `ACC` and stays there while the engine runs, the tick turning green. Getting into a car, the key is already where the car's state says it is.

## Turning the key

The key has two positions before the engine. With the engine off, a tap of `Y` as the driver turns it to **ACC**: the dashboard wakes with the 0.7 second bulb check, and a second tap switches it off again. Holding `Y` for 0.3 seconds goes through ACC and cranks the engine; a start that fails leaves the key in ACC. Pressing `Y` while the engine runs stops it and takes the key fully off. ACC drains the battery slowly (see [Car Batteries & Starters](Car-Batteries-and-Starters)) and stays on when you get out, like the headlights.

Each turn of the key has a sound that goes with what the dashboard shows, heard by the driver: a relay clunk for ACC; a starter whirr that speeds up as the engine catches; weak solenoid chatter on a flat battery; a solid clunk on every try with a dead starter motor; an uneven grinding with a wrecked engine; an even crank that never catches on an empty tank; and a shudder that slows and ends in a clunk when the engine stalls. With no battery there is no sound at all.

Cranking plays the outcome:

- **It starts.** Every lamp lights for 0.7 seconds, the bulb check, the starter turns, the needle catches and settles at idle.
- **No battery.** Nothing happens at all: the dashboard stays dark.
- **Flat battery** (under 10 %). The backlight flickers, the starter solenoid clicks and the rev needle twitches with each click while the voltmeter sags. The action text reads *The battery is flat*.
- **Wrecked engine** (300 health or less). The bulbs check, the starter grinds unevenly for 2 seconds and the engine lamp stays lit for 4 seconds.
- **Empty tank.** The bulbs check, the starter turns evenly for 2 seconds and never catches, and the fuel lamp stays lit for 4 seconds.
- **Dead starter motor.** The engine only clicks and the message says so; see [Car Batteries & Starters](Car-Batteries-and-Starters).

The battery is checked first, then damage and fuel, then the starter motor, so a car with a flat battery shows nothing about its other faults until it has a charge.

## Stalling

When the engine dies under you, the rev needle drops, the engine lamp lights for a second and a half (not for an empty tank, which is no fault), and the lamp for the cause flashes red for 4 seconds: the fuel lamp for an empty tank, the engine lamp for damage, a plain stall, or a battery pulled or flattened by an [EMP](Explosives).
