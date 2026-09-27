# Third-party notices

## Scavenge & Survive (upstream gamemode)
Files under `resources/[scavengesurvive]/data/generated/` and `sql/seed/` are generated from data in
https://github.com/Southclaws/ScavengeSurvive (commit 399ba8e8fd164243b32fb694f4bb6ce37fe40c35),
Copyright (C) Barnaby "Southclaws" Keene, Mozilla Public License 2.0 (see `LICENSE-MPL-2.0`).
Upstream asks that credits, including in-game credit messages, are kept.

## Scavenge & Survive maps
`scriptfiles/maps/**` upstream is CC BY-SA 4.0 (see `LICENSE-CC-BY-SA-4.0`). Not used by the MVP.

## SA-MP custom object models
SA-MP's object models (ids 18631–19999) are covered by the SA-MP licence, which forbids redistribution.
This repository never contains them; `resources/[scavengesurvive]/models/files/` is git-ignored and is
filled by `tools/extract-samp-models.ps1` from a locally installed SA-MP client (post-MVP).

## Everything else
New code in this repository is released under the Unlicense (see `LICENSE`).
