# Aimshout

Aimshout lets you say a short, preset line to other players without opening the chat box, so you never have to take your hands off the aim and fire controls when you meet someone while holding a weapon.

## Setting your line

Type `/aimshout` followed by your message, for example:

`/aimshout I mean no harm. Drop your weapon and tell me your name.`

The server confirms with `AimShout set to '...'`. Typing `/aimshout` alone shows the usage. The line is kept until you disconnect, so set it again after logging in.

Your line is cleaned before it is stored: colour codes and control characters are removed, it is cut to one line, and it can be at most 128 characters.

## Sending it

Press **Aim** and **Look Behind** at the same time (right mouse button and middle mouse button by default). In a vehicle, press **Look Behind** and the **Horn** together instead.

The line is sent as normal local chat, whatever chat mode you are in, so only nearby players see it (see [Commands](Commands) and [Controls](Controls) for the other chat commands and keys). You can send one about every three-quarters of a second.
