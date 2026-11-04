# Drugs

Drugs come from [Pills](Medical), [Injectors](Medical) and the Doctor's Bag. Each one lasts 5 minutes. Taking the same drug again adds another 5 minutes instead of resetting the timer, so doses stack. Active drugs are listed in yellow in the Health Status panel (open the inventory with `H`), they are saved when you log out and carry on counting down when you return, and you are told when one wears off. Dying clears them.

![Pills](images/items/2709_pain_killer.png) ![Injector](images/items/2711_tatoo_needle.png) ![Doctor's Bag](images/items/11738_mediccase1.png)

## Taking them

Hold the interact key (`F`) with the item in your hands.

- **Pills** take 1 second and always act on you. The type shows in the name: `Pills (Antibiotics)`, `Pills (Painkiller)` or `Pills (LSD)`.
- **Injectors** take 1 second and can be used on yourself or on a player next to you. The type shows in the name: `Injector (Morphine)`, `Injector (Adrenaline)`, `Injector (Heroin)` or `Injector (Empty)`. After use the injector stays in your hands, now empty.
- **Doctor's Bag** gives the drug named in its label, for example `Doctor's Bag (2/3, Morphine)`: two charges left, and each use spends one.

Pills and injectors found in loot are random; ones given by staff or crafted are Antibiotics and Empty.

## Effects

| Drug | Source | Effect |
|:--|:--|:--|
| Antibiotic | Antibiotics pills, Doctor's Bag | the pills cure a food [infection](Infection) and, half the time, a wound infection |
| Painkill | Painkiller pills, Doctor's Bag | pills restore 10 health; hides the dark screen from low health |
| Morphine | Morphine injector, Doctor's Bag | restores 0.5 health on most seconds; calms the infection wobble; slightly blurs the screen |
| Adrenaline | Adrenaline injector, Doctor's Bag | restores a little health every second; hides the dark screen; calms the infection wobble; injected into an unconscious player it wakes them up (not when used on yourself) |
| Heroin | Heroin injector | the sky turns to night with a fixed weather |
| LSD | LSD pills | the sky turns to night with a fixed weather |
| Air | Empty injector | costs 1 health on half of the seconds and heavily blurs the screen |

When the last of LSD or Heroin wears off the sky goes back to the server's time and weather.

An empty injector is not a harmless item: it injects air. Check the name before using one on someone else.
