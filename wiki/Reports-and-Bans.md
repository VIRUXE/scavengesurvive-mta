# Reports & Bans

The staff keep the server playable. This page covers how you reach them, what they can do to you, and how to appeal a ban. What the server does by itself is on [Fair Play](Fair-Play).

## The staff

`/admins` lists every staff account, its rank and who is online right now. Ranks, lowest to highest: Game Master, Moderator, Administrator, Lead, Developer.

A staff member **on duty** wears a fixed staff skin, takes no damage from players and sees a name tag with name, health and distance over every player. Off duty they play like anyone else.

## Reporting a player

`/report` with nothing after it opens a menu with four choices: a player who is online, a player's name (someone who is offline), the player who last killed you, or the player closest to you. Pick one, then type the reason (up to 128 characters). To skip the menu:

| Command | Reports |
|:--|:--|
| `/report <name> [reason]` | that player, online or not (a partial name is enough for someone online) |
| `/report near [reason]` | the closest player within 100 m (staff on duty do not count) |
| `/report killer [reason]` | whoever last killed you |

Without a reason on the command line a window asks for it. *Report filed. Thank you.* confirms it; the staff see it at once if any are online and in their report list otherwise, together with where you (or the reported player) stood. You cannot report yourself.

## Reporting a bug

`/bug <description>` (or `/bug` alone, which opens a window) files a bug report of up to 128 characters. `/issues` lists the open bug reports and opens one; Moderators and above can delete a report from there.

## What the staff can do

| Action | What you see |
|:--|:--|
| **Message** | ` >  text` lines in chat: a message to you, or an announcement to everyone. |
| **Mute** | *Muted from global chat for N seconds, Reason: ...* (or permanently). While muted you cannot send any chat line or use voice; trying tells you the time left. Mutes are saved on your account, so leaving does not lift them. |
| **Warn** | *You been warned (n/5) for: reason.* The fifth warning is a 24 hour ban. |
| **Kick** | *Kicked, reason: ...* and you are disconnected. You keep your character. |
| **Freeze** | *Frozen by admin* (or *for N seconds*): you cannot move or act until *You are now unfrozen.* |
| **Teleport** | Staff can bring you to them or go to where a report was filed. |
| **Heal** | *You were healed by staff.* |
| **Spectate** | Nothing: an invisible staff member may be watching. |
| **Ban** | *You are banned! Reason: ...*, then you are disconnected. |

## Bans

A ban is recorded against your name, your address and your computer, for a set time or forever. Joining while it stands shows `You are banned (since <date> by <staff>).`, the reason and `Unban: <date>` or `Never`, and disconnects you; see [Account & Login](Account-and-Login).

- A warning ban (*Getting 5 warnings*) runs out by itself after 24 hours.
- A ban aimed at someone who shared your address or computer can catch you by mistake; the join message names the banned account, so note it.

### Appealing

Contact a Moderator or above (see `/admins`, or the community's Discord) with the name you were banned under, the date and the reason shown. The staff check the history behind the ban before deciding: a shared-address catch is lifted and reissued against the right person, a timed ban is explained with its end date. The staff member who issued the ban does not decide alone.
