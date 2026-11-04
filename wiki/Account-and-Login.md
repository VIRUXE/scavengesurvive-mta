# Account & Login

Your account is your MTA nickname: the name you connect with is the name you register, and every later connection with that name asks for its password. A nickname is 1 to 22 characters long, letters, digits and punctuation only.

## First join

1. **Language.** A window lists the ten languages of the interface. Pick yours and press **Continue** (double-clicking or `Enter` works too). The choice is saved on the account once you are in; change it later with `/lang`.
2. **Register.** The dialog *Register For A New Account* asks for a password of 4 to 32 characters. **Accept** creates the account and logs you in. **Leave** disconnects you.
3. **Welcome.** New accounts read the welcome text. Its only button counts down from 10 before it reads **Accept**; closing it earlier just brings it back. `/welcome` shows it again any time.
4. Your first character spawns; see [Death](Death) for what a new character starts with.

![Register dialog](images/screens/auth-dialog-register.jpg)

## Logging in

Every later join shows *Login To Your Account*. Type the password and press **Accept** (or `Enter`); **Leave** (or `Escape`) disconnects you.

![Login dialog](images/screens/auth-dialog-login.jpg)

A wrong password, or one shorter than 4 characters, counts as a try: *Incorrect password! N out of 5 tries*. The fifth wrong try disconnects you, and the tries are counted per computer for 10 minutes, so reconnecting does not reset them.

![Wrong password](images/screens/auth-dialog-wrong-password.jpg)

Only one session per account: a second client connecting with your name is refused (*Account already online*). A deactivated account is refused with *Account inactive*; ask the staff.

The server can turn on automatic login for players returning from the same address and computer as their last login; it is off by default, so expect the password dialog.

Once you are in, your character loads where you left it, with its stats and inventory; after a death a new one is created.

## Commands

`/changepass <old> <new>` changes your password (the new one must be 4 to 32 characters; a wrong old password is refused), `/lang <code>` sets your language (`en`, `es`, `fr`, `pt`, `ptbr`, `ru`, `ro`, `id`, `bhs` or `cs`; lines not translated yet show in English), `/tooltips` turns the help tips on or off and `/welcome` shows the welcome text again. All four are saved on your account; see [Commands](Commands).

## Bans

When you connect, the server checks your name, your address and your computer against the ban list. A match shows three lines, `You are banned (since <date> by <staff>).`, `Reason: ...` and `Unban: <date>` or `Never`, and disconnects you a second later. See [Reports & Bans](Reports-and-Bans) for appeals.

## Whitelist

The server normally lets everyone in. When the staff turn the whitelist on, only listed names and staff accounts may play:

- logging in while it is on and you are not listed prints *Whitelist active.* and *You are not in the whitelist.* and disconnects you;
- if it turns on while you are playing, a countdown appears at the top of the screen, *Not whitelisted / Time remaining mm:ss*, and you are disconnected when it reaches zero (5 minutes by default). Being added to the list in the meantime stops it.

See also [Getting Started](Getting-Started), [Death](Death) and [Commands](Commands).
