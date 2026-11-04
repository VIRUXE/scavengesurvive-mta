# Medical

![Medical supplies: Dirty and Antiseptic Bandages, a Medkit, a Doctor's Bag, Pills and an Injector](images/scenes/medical.png)

Medical items stop bleeding, close wounds, cure infections and apply [drugs](Drugs). Hold the item and hold `F`: a progress bar runs, and letting go cancels it. If another player stands within 1.5 m of you, you treat them; otherwise you treat yourself. Pills are always taken by yourself.

![Dirty Bandage](images/items/11747_bandage1.png) ![Antiseptic Bandage](images/items/11748_bandagepack1.png) ![Medkit](images/items/11736_medicalsatchel1.png) ![Doctor's Bag](images/items/11738_mediccase1.png) ![Pills](images/items/2709_pain_killer.png) ![Injector](images/items/2711_tatoo_needle.png)

## Treatment time

| Patient | Time |
|:--|--:|
| Yourself, or another player who is awake | 4 s |
| A knocked-out player | 6 s |
| Taking pills or using an injector | 1 s |

The [Medical skill](Skills) shortens the bandage, medkit and bag times. The treatment is cancelled if you move more than about 0.8 m, if the patient walks more than 2.5 m away, if you change the item in your hands, or if either of you dies or leaves.

## Items

| Item | Size | Effect |
|:--|--:|:--|
| Dirty Bandage | 2 | Reduces the bleed rate and is used up. One time in three the wound becomes infected. Does nothing when there is no bleeding. |
| Antiseptic Bandage | 2 | Reduces the bleed rate like a bandage and cures a [wound infection](Infection). Used up if it did either. A character created after a death starts with one (see [Death](Death)). |
| Medkit | 1 | Reduces the bleed rate and closes wounds: 1 to 2 on yourself, 2 to 3 on someone else. Used up. |
| Doctor's Bag | 3 | Stops the bleeding completely, cures wound infection and closes wounds: 1 to 2 on yourself, 3 to 5 on someone else. Has up to 3 charges and is used up with the last one. Each charge also applies the bag's drug (antibiotic, painkiller, morphine or adrenaline). |
| Pills | 1 | Antibiotics cure a food infection and, half the time, a wound infection. Painkillers give 10 health. LSD is a hallucinogen. The type is shown in the name, for example `Pills (LSD)`. |
| Injector | 1 | Morphine, adrenaline or heroin, shown in the name. Adrenaline wakes a knocked-out player (not yourself). Afterwards the injector is empty, and an empty injector injects air. |

## How much a bandage helps

Bandages and the Medkit cut the bleed rate by a fraction that depends on how high it is: a bleed of 0.5 drops to about 0.38, while a bleed of 0.1 drops to about 0.02. A rate that falls under 0.005 stops entirely. Very heavy bleeding barely improves with one bandage, so bandage early and often. The Health Status panel in the [inventory](Inventory) shows the current rate.

Each wound you carry makes a knockout more likely (see [Bleeding & Wounds](Bleeding-and-Wounds)), so closing them with a Medkit or Doctor's Bag also lowers that chance.

## Making a bandage

Combine a Combat Knife (kept) with Clothes to cut a Dirty Bandage; see [Combining](Combining). Bandages are also a Molotov ingredient (see [Explosives](Explosives)).

See also [Health](Health), [Infection](Infection) and [Drugs](Drugs).
