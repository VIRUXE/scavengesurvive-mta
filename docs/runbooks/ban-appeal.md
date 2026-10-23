# Ban appeal

**When:** a player reports they are kicked on join with `You are banned (since … by …)`, or asks for a ban to be
lifted. Level 2 (Moderator) or above handles it; the staff member who issued the ban is consulted but does not
decide alone.

**Prerequisites:** staff level 2 in game, or read access to MariaDB.

## Steps

1. Identify the ban. In game: `/banned <name>` prints the newest active ban (date, by whom, expiry, reason). In
   SQL: `SELECT * FROM bans WHERE active = 1 AND (name = 'X' OR ip = '…' OR serial = '…') ORDER BY created_at DESC`.
   A player can be caught by an IP or serial ban issued against another name: the kick line names the banned
   account, so compare it with the name they joined with.
2. Read the history: `/history <name>` (connections: date, IP, serial) and `/aliases <name>` (other names from
   the same IP or serial), `/profile <name>` (warnings, reports). In SQL the full audit is `SELECT * FROM
   staff_actions WHERE target_name = 'X' ORDER BY created_at` and `SELECT * FROM bans FOR SYSTEM_TIME ALL WHERE
   name = 'X'` (every edit of the ban rows).
3. Decide. Warning bans (`Getting 5 warnings`) expire by themselves after `staff.warn_ban_hours`; tell the
   player when (`expires_at`). A shared-IP catch (family, LAN) with a different serial is lifted and the ban
   re-issued on the serial only when the evidence says the original target is someone else.
4. Lift: `/unban <name>` (deactivates every active ban on that name and logs `unban`). For an IP-only catch where
   the named account must stay banned: `UPDATE bans SET ip = NULL WHERE id = <id>` and log it with
   `exports.staff:logAction("<you>", "ban_edit", "<name>", "ip cleared: shared address")` via `rcon.ps1 lua`.
5. Tell the player and note the outcome in the report thread if there was one (`/reports`, then `View`).

## Rollback

Re-ban with the original reason and remaining duration: `/ban <name> <duration> <reason>`; the previous row stays
in history (`active = 0`).

## Escalation

Lead (level 4) for bans issued by level 3 staff; the repository owner for a ban that involves a staff account.
