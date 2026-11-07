# Combat Log

Combat logging is quitting the game during a fight to escape being killed and losing your items. The server counts it as a death.

## The combat window

When another player wounds you, a 30 second window opens (the server can change the length). While it is open the clock on your HUD turns red, and it turns white again when the window closes or when the player who hit you leaves.

If you disconnect, quit or time out while the window is open **and the player who hit you is still online**:

- everyone sees `<name> combat logged!` in chat;
- your character dies on the spot: your items, worn gear and hands drop where you stood, exactly like a normal death (see [Death](Death));
- your next login starts a new character, and your [skills](Skills) are gone.

## What does not count

- Being kicked or banned by staff: your character is saved normally.
- Damage that did not come from a player (a fall, hunger) does not turn the clock red. It only matters if a player had hit you earlier, in which case it keeps that window going.
- If the attacker has already left the server, there is nobody to escape from and your character is saved normally.
- Dying by other means first: a dead character cannot combat log.

## Lost connections

A dropped connection counts like quitting: the check happens when the server notices you are gone, and any hit by a player in the last 30 seconds (whose attacker is still online) kills the character.
