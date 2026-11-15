# Separate hunger and thirst
Approved: independent persisted thirst restored by drinks, blue bar above green hunger.
Use 0–100 hydration named thirst, with the same initial values and movement drain as food. Low hydration damages health using the existing starvation curve. Bleeding and starvation retain priority in death attribution. Drinks restore thirst rather than food; preserve negative food effects for dangerous liquids. Existing characters start at 80 hydration.
## Approach
Extend character state, sync, persistence and HUD. Stack thirst and hunger beneath stock health to avoid stock armour. Preserve duty and reauthentication protections. No new tests per CLAUDE.md; verify using direct Lua checks, lint and SQL rollback checks.
