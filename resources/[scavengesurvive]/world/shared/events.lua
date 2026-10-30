-- client to server (handlers registered with net.handler); keypadSubmitted is building's keypad UI answering for
-- the code hunt's lockup
addEvent("buttonPressed", true)
addEvent("buttonsStateRequested", true)
addEvent("keypadSubmitted", true)

-- server to client
addEvent("buttonsStateChanged", true)
addEvent("buttonMessageShown", true)
addEvent("buttonViewToggled", true)
addEvent("puzzleKeypadSparked", true)
addEvent("puzzleSparkShown", true)
addEvent("keypadHackStarted", true)
addEvent("keypadHackEnded", true)
addEvent("keypadOpened", true)
addEvent("keypadClosed", true)
addEvent("toastShown", true)

-- server-local (triggered and handled on one side, or between resources)
addEvent("weatherChanged", false)
