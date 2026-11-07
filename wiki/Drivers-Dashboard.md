# Driver's Dashboard

While you drive a vehicle with an engine and a fuel tank, a small black strip sits at the bottom centre of the screen: four warning lamps above a segmented rev counter and a voltmeter. It is lit from the state of the vehicle you sit in and plays out what happens when you turn the key, so each way a start can fail looks different. Only the driver sees it. The vehicle panel in the bottom right corner ([HUD](HUD)) still shows doors, engine, damage, fuel and speed.

<!-- shot:shot-dashboard -->

## The lamps

Left to right. A lamp stays dark until something is wrong; it then glows, flashes slowly (once a second) or fast (four times a second).

| Lamp | Colour | Lit when |
|:--|:--|:--|
| `BAT` | red | the battery is under 25 % (slow flash) or under 10 % (fast flash). Steady while the headlights are on with the engine off: they are draining the battery |
| `CHK` | amber | the vehicle is worn (650 health or less, steady), broken (450 or less, slow flash) or wrecked (300 or less, a fast red flash) |
| `FUEL` | amber | the tank is at 15 % or less (steady), 5 % or less (slow flash) or empty (a fast red flash) |
| `LGT` | green | the headlights are on |

The thresholds are the ones that matter when you drive: under 450 health the engine can cut out at speed, at 300 or less it will not start, under 10 % the battery will not turn it over. See [Vehicles](Vehicles), [Fuel](Fuel) and [Car Batteries & Starters](Car-Batteries-and-Starters).

## Rev counter and voltmeter

The row below the lamps reads `RPM`, then 22 segments that fill from the left: white, amber past about two thirds of the scale and red past 85 %. The needle follows your speed within the current gear, climbing through each gear and dropping back at the shift; standing still with the throttle pressed it rises a little. It lags behind the engine and falls faster than it climbs. With the engine off it rests at zero.

The voltmeter on the right shows `14.1V` while the engine runs and charges the battery. With the engine off it reads the battery's resting voltage, `11.6V` empty to `12.7V` full, amber under 11.9 V and red under 11.0 V. Vehicles without a battery (motorbikes, boats, the open vehicles without doors) read as if theirs were always full.

The strip is dark until the key is turned to ACC or the engine runs, dim in ACC and bright while the engine runs. With no battery under the bonnet the dashboard is dead: every lamp dark, the rev counter empty, the voltmeter reading `--.-V`.

## The ignition switch

A small square to the left of the strip shows the ignition cylinder. Four ticks sit around it, `OFF`, `ACC`, `ON` and `START` from left round to right, and the key turns to the one it is in; the lit tick is grey, amber, green or red to match. The key goes to `START` while the starter turns, then springs back to `ON` if the engine caught, or to `ACC` if the start failed. Getting into a car, the key is already where the car's state says it is.

## Turning the key

The key has two positions before the engine. With the engine off, a tap of `Y` as the driver turns it to **ACC**: the dashboard wakes with the 0.7 second bulb check, and a second tap switches it off again. Holding `Y` for 0.3 seconds goes through ACC and cranks the engine; a start that fails leaves the key in ACC. Pressing `Y` while the engine runs stops it and takes the key fully off. ACC drains the battery slowly (see [Car Batteries & Starters](Car-Batteries-and-Starters)) and stays on when you get out, like the headlights.

Each turn of the key has a sound that goes with what the dashboard shows, heard by the driver: a relay clunk for ACC; a starter whirr that speeds up as the engine catches; weak solenoid chatter on a flat battery; a solid clunk on every try with a dead starter motor; an uneven grinding with a wrecked engine; an even crank that never catches on an empty tank; and a shudder that slows and ends in a clunk when the engine stalls. With no battery there is no sound at all.

Cranking plays the outcome:

- **It starts.** Every lamp lights for 0.7 seconds, the bulb check, the starter turns, the needle catches and settles at idle.
- **No battery.** Nothing happens at all: the dashboard stays dark.
- **Flat battery** (under 10 %). The backlight flickers, the starter solenoid clicks and the needle twitches with each click while the volts sag; then `BAT` flashes fast for 4 seconds. The action text reads *The battery is flat*.
- **Wrecked engine** (300 health or less). The bulbs check, the starter grinds unevenly for 2 seconds and `CHK` flashes fast for 4 seconds.
- **Empty tank.** The bulbs check, the starter turns evenly for 2 seconds and never catches, and `FUEL` flashes for 4 seconds.
- **Dead starter motor.** The engine only clicks and the message says so; see [Car Batteries & Starters](Car-Batteries-and-Starters).

The battery is checked first, then damage and fuel, then the starter motor, so a car with a flat battery shows nothing about its other faults until it has a charge.

## Stalling

When the engine dies under you, the needle drops, `BAT` and `CHK` light for a second and a half as the alternator stops, and the lamp for the cause flashes for 4 seconds: `FUEL` for an empty tank, `CHK` for damage, `BAT` when the battery was pulled or flattened by an [EMP](Explosives).
