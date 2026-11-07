# Car Batteries & Starters

![Car Battery](images/items/20208_car_battery.png) ![Starter Motor](images/items/2006_cr_safe_dial.png)

Two parts under the bonnet decide whether an engine turns over: the **battery** and the **starter motor**. Every vehicle with an engine under a bonnet has both (cars, trucks, vans, helicopters and planes); motorbikes, bicycles, boats and the open vehicles without doors (BF Injection, Bandito, Baggage...) have neither and need neither. The items are [Car Battery](Car-Battery) and [Starter Motor](Starter-Motor); the lamps that show their state are on [Driver's Dashboard](Drivers-Dashboard).

## The bonnet

With empty hands, tap `F` at the front of an unlocked vehicle to open or shut the bonnet (a locked one says *The bonnet is locked: unlock the vehicle first*). Everything below is done at the open bonnet. Repairs need it open too; see [Repairing & Locks](Repairing-and-Locks).

## Battery

A vehicle found in the world holds a charge of 15 to 100 %. The engine needs at least 10 % to turn over: below that the key gives *The battery is flat*, and a vehicle with no battery does not react. The headlights run off the battery too: with the engine off they only come on at 10 % or more, and go out when the charge falls below it.

| Situation | Charge |
|:--|:--|
| Parked, engine off | nothing lost for 24 hours after the engine last ran, then 1 % per hour |
| Headlights on, engine off | 12 % per hour from the first second |
| Engine running, standing still | gains 2.5 % per minute |
| Engine running, driving (above 5 km/h) | gains 10 % per minute, so an empty battery is full after about ten minutes on the road |

**Taking it out:** with the bonnet open and empty hands, hold `F` for half a second. A 3 second job follows and the Car Battery is in your hands, named with its charge (*Car Battery (63%)*). If the engine was running it stops. A vehicle without a battery says so.

**Fitting one:** hold a Car Battery at the open bonnet and press `F`, 3 seconds. A vehicle that already has one refuses it. The battery brings the charge it carries; a loose one found as loot holds 15 to 100 %, and charge is kept while a battery is carried or lies about. Swapping a flat battery for a charged one from another vehicle is the quick way to get a car going.

**EMPs:** an [EMP](Explosives) going off within 12 m switches the engine off and drains the installed battery to 0 %; the headlights go out with it. The car cannot start again until a charged battery is fitted; taking the flat one out and putting it back does not restore it, and the flat charge survives a server restart.

## Starter motor

Every successful engine start wears the starter motor. A fresh one lasts a random 60 to 400 starts; once its life is spent the key only clicks (*The engine won't turn over: the starter motor is dead*). Battery, fuel and lights are untouched; only the start is gone. About 2 % of vehicles spawn with a dead starter, so a car that will not start with a good battery, fuel and a working engine has probably spent it.

**Replacing it:** hold a Starter Motor at the open bonnet of an unlocked vehicle with the engine off and press `F`. The hold takes 6 seconds, shorter with the Repair [skill](Skills); the item is used up and the vehicle gets a fresh starter with a new random life. A vehicle whose starter still works refuses the part. There is no way to see how many starts are left: the first sign is the click.

## Why a car will not start

The checks run in this order; the first that fails is the one you are told about:

1. No battery, or a battery under 10 %.
2. The vehicle is wrecked (300 health or less) or the tank is empty; see [Vehicles](Vehicles) and [Fuel](Fuel).
3. The starter motor is dead.

Every start that gets past the first two costs the starter motor one, even a start made just to check.

See also [Vehicles](Vehicles), [Repairing & Locks](Repairing-and-Locks) and [Explosives](Explosives).
