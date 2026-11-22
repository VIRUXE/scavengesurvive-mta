-- Removable vehicle body parts: which models have them, where each slot sits on the car and how a slot's saved state
-- reads. Pure logic: no MTA calls at file scope. A model joins by getting an entry in MODELS (and its part items:
-- <prefix><Slot>Good / <prefix><Slot>Bad). The Bobcat's were placed by hand (tools/bobcat_parts.py); every other car's
-- come from tools/car_parts.py (print models), measured from its own panels. Models whose bodies match share one
-- set of items by sharing a prefix (Police LS and SF, Rancher and Ranger).
local M = {}

M.REACH = 1.8 -- metres from a slot's point within which a player can work on it
M.DOOR_MISSING = 4 -- setVehicleDoorState: 0 intact .. 4 gone
M.PANEL_MISSING = 3 -- setVehiclePanelState: 0 intact .. 3 gone

-- door: MTA door id (0 bonnet, 1 boot, 2..5 the side doors); panel: MTA panel id (5 front bumper, 6 rear bumper)
-- x, y: the slot's point in the vehicle's local frame; groundDrop: metres from the origin down to the ground
M.MODELS = {
    [422] = {
        prefix = "Bobcat",
        groundDrop = 0.7,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.4 },
            { name = "Tailgate", door = 1, x = 0, y = -2.2 },
            { name = "LeftDoor", door = 2, x = -1.05, y = 0.25 },
            { name = "RightDoor", door = 3, x = 1.05, y = 0.25 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.25 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.35 },
        },
    },
    [403] = {
        prefix = "Linerunner",
        groundDrop = 1.3,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 3.132 },
            { name = "LeftDoor", door = 2, x = -0.84, y = 1.727 },
            { name = "RightDoor", door = 3, x = 0.84, y = 1.727 },
            { name = "FrontBumper", panel = 5, x = 0, y = 4.353 },
        },
    },
    [405] = {
        prefix = "Sentinel",
        groundDrop = 0.6,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.475 },
            { name = "Trunk", door = 1, x = 0, y = -2.444 },
            { name = "LeftDoor", door = 2, x = -1.049, y = 0.225 },
            { name = "RightDoor", door = 3, x = 1.049, y = 0.225 },
            { name = "RearLeftDoor", door = 4, x = -0.896, y = -0.899 },
            { name = "RearRightDoor", door = 5, x = 0.896, y = -0.899 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.449 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.645 },
        },
    },
    [407] = {
        prefix = "Firetruck",
        groundDrop = 1,
        slots = {
            { name = "LeftDoor", door = 2, x = -1.36, y = 3.206 },
            { name = "RightDoor", door = 3, x = 1.36, y = 3.206 },
            { name = "FrontBumper", panel = 5, x = 0, y = 4.36 },
        },
    },
    [416] = {
        prefix = "Ambulance",
        groundDrop = 0.9,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 2.225 },
            { name = "LeftDoor", door = 2, x = -1.394, y = 1.106 },
            { name = "RightDoor", door = 3, x = 1.395, y = 1.106 },
            { name = "RearLeftDoor", door = 4, x = -0.73, y = -3.636 },
            { name = "RearRightDoor", door = 5, x = 0.73, y = -3.636 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.955 },
        },
    },
    [418] = {
        prefix = "Moonbeam",
        groundDrop = 0.833,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.886 },
            { name = "Trunk", door = 1, x = 0, y = -2.303 },
            { name = "LeftDoor", door = 2, x = -1.188, y = 0.805 },
            { name = "RightDoor", door = 3, x = 1.188, y = 0.805 },
            { name = "RearLeftDoor", door = 4, x = -1.026, y = -0.542 },
            { name = "RearRightDoor", door = 5, x = 1.027, y = -0.542 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.523 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.431 },
        },
    },
    [424] = {
        prefix = "BfInjection",
        groundDrop = 0.54,
        slots = {
            { name = "FrontBumper", panel = 5, x = 0, y = 1.69 },
            { name = "RearBumper", panel = 6, x = 0, y = -1.687 },
        },
    },
    [427] = {
        prefix = "Enforcer",
        groundDrop = 0.798,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 2.371 },
            { name = "LeftDoor", door = 2, x = -1.252, y = 1.245 },
            { name = "RightDoor", door = 3, x = 1.252, y = 1.245 },
            { name = "RearLeftDoor", door = 4, x = -0.628, y = -3.543 },
            { name = "RearRightDoor", door = 5, x = 0.628, y = -3.543 },
            { name = "FrontBumper", panel = 5, x = 0, y = 3.301 },
        },
    },
    [433] = {
        prefix = "Barracks",
        groundDrop = 1.2,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 2.904 },
            { name = "LeftDoor", door = 2, x = -1.011, y = 1.391 },
            { name = "RightDoor", door = 3, x = 1.009, y = 1.391 },
            { name = "FrontBumper", panel = 5, x = 0, y = 4.044 },
            { name = "RearBumper", panel = 6, x = 0, y = -4.34 },
        },
    },
    [440] = {
        prefix = "Rumpo",
        groundDrop = 0.903,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.977 },
            { name = "LeftDoor", door = 2, x = -1.083, y = 1.04 },
            { name = "RightDoor", door = 3, x = 1.083, y = 1.04 },
            { name = "RearLeftDoor", door = 4, x = -0.675, y = -2.576 },
            { name = "RearRightDoor", door = 5, x = 0.675, y = -2.576 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.599 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.486 },
        },
    },
    [455] = {
        prefix = "Flatbed",
        groundDrop = 1.2,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 2.853 },
            { name = "LeftDoor", door = 2, x = -1.011, y = 1.391 },
            { name = "RightDoor", door = 3, x = 1.009, y = 1.391 },
            { name = "FrontBumper", panel = 5, x = 0, y = 4.033 },
            { name = "RearBumper", panel = 6, x = 0, y = -4.328 },
        },
    },
    [456] = {
        prefix = "Yankee",
        groundDrop = 0.8,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 2.617 },
            { name = "Trunk", door = 1, x = 0, y = -4.305 },
            { name = "LeftDoor", door = 2, x = -1.093, y = 1.556 },
            { name = "RightDoor", door = 3, x = 1.093, y = 1.557 },
            { name = "FrontBumper", panel = 5, x = 0, y = 3.468 },
            { name = "RearBumper", panel = 6, x = 0, y = -4.34 },
        },
    },
    [470] = {
        prefix = "Patriot",
        groundDrop = 0.56,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.19 },
            { name = "Tailgate", door = 1, x = 0, y = -2.293 },
            { name = "LeftDoor", door = 2, x = -1.312, y = 0.142 },
            { name = "RightDoor", door = 3, x = 1.312, y = 0.142 },
            { name = "RearLeftDoor", door = 4, x = -1.07, y = -0.884 },
            { name = "RearRightDoor", door = 5, x = 1.07, y = -0.884 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.16 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.412 },
        },
    },
    [475] = {
        prefix = "Sabre",
        groundDrop = 0.5,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.422 },
            { name = "Trunk", door = 1, x = 0, y = -2.529 },
            { name = "LeftDoor", door = 2, x = -1.091, y = -0.013 },
            { name = "RightDoor", door = 3, x = 1.091, y = -0.013 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.418 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.61 },
        },
    },
    [478] = {
        prefix = "Walton",
        groundDrop = 0.7,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.452 },
            { name = "Tailgate", door = 1, x = 0, y = -2.333 },
            { name = "LeftDoor", door = 2, x = -1.052, y = 0.319 },
            { name = "RightDoor", door = 3, x = 1.052, y = 0.319 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.248 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.403 },
        },
    },
    [479] = {
        prefix = "Regina",
        groundDrop = 0.535,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.521 },
            { name = "Trunk", door = 1, x = 0, y = -2.534 },
            { name = "LeftDoor", door = 2, x = -1.106, y = 0.237 },
            { name = "RightDoor", door = 3, x = 1.106, y = 0.237 },
            { name = "RearLeftDoor", door = 4, x = -0.932, y = -0.901 },
            { name = "RearRightDoor", door = 5, x = 0.932, y = -0.901 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.635 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.686 },
        },
    },
    [480] = {
        prefix = "Comet",
        groundDrop = 0.5,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.256 },
            { name = "Trunk", door = 1, x = 0, y = -2.104 },
            { name = "LeftDoor", door = 2, x = -1.054, y = -0.048 },
            { name = "RightDoor", door = 3, x = 1.054, y = -0.048 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.346 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.359 },
        },
    },
    [489] = {
        prefix = "Rancher",
        groundDrop = 0.914,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.536 },
            { name = "Tailgate", door = 1, x = 0, y = -2.466 },
            { name = "LeftDoor", door = 2, x = -1.312, y = 0.149 },
            { name = "RightDoor", door = 3, x = 1.312, y = 0.149 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.652 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.611 },
        },
    },
    [599] = {
        prefix = "Rancher",
        groundDrop = 0.914,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.536 },
            { name = "Tailgate", door = 1, x = 0, y = -2.466 },
            { name = "LeftDoor", door = 2, x = -1.312, y = 0.149 },
            { name = "RightDoor", door = 3, x = 1.312, y = 0.149 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.652 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.611 },
        },
    },
    [495] = {
        prefix = "Sandking",
        groundDrop = 1.05,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.48 },
            { name = "Tailgate", door = 1, x = 0, y = -1.969 },
            { name = "LeftDoor", door = 2, x = -1.381, y = 0.288 },
            { name = "RightDoor", door = 3, x = 1.379, y = 0.288 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.47 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.083 },
        },
    },
    [496] = {
        prefix = "Blista",
        groundDrop = 0.468,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.266 },
            { name = "Trunk", door = 1, x = 0, y = -1.88 },
            { name = "LeftDoor", door = 2, x = -1.127, y = 0.003 },
            { name = "RightDoor", door = 3, x = 1.127, y = 0.003 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.232 },
            { name = "RearBumper", panel = 6, x = 0, y = -1.96 },
        },
    },
    [498] = {
        prefix = "Boxville",
        groundDrop = 0.76,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 2.583 },
            { name = "LeftDoor", door = 2, x = -1.399, y = 1.534 },
            { name = "RightDoor", door = 3, x = 1.399, y = 1.534 },
            { name = "RearLeftDoor", door = 4, x = -0.603, y = -3.012 },
            { name = "RearRightDoor", door = 5, x = 0.603, y = -3.012 },
            { name = "FrontBumper", panel = 5, x = 0, y = 3.049 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.904 },
        },
    },
    [500] = {
        prefix = "Mesa",
        groundDrop = 0.82,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.205 },
            { name = "Tailgate", door = 1, x = 0, y = -1.923 },
            { name = "LeftDoor", door = 2, x = -1.026, y = 0.008 },
            { name = "RightDoor", door = 3, x = 1.026, y = 0.008 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.205 },
            { name = "RearBumper", panel = 6, x = 0, y = -1.771 },
        },
    },
    [504] = {
        prefix = "Bloodring",
        groundDrop = 0.5,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.639 },
            { name = "Trunk", door = 1, x = 0, y = -2.713 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.622 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.801 },
        },
    },
    [508] = {
        prefix = "Journey",
        groundDrop = 1.1,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 2.422 },
            { name = "LeftDoor", door = 2, x = -1.451, y = 1.633 },
            { name = "RightDoor", door = 3, x = 1.451, y = 1.633 },
            { name = "RearRightDoor", door = 5, x = 1.27, y = 0.214 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.917 },
            { name = "RearBumper", panel = 6, x = 0, y = -3.721 },
        },
    },
    [515] = {
        prefix = "Roadtrain",
        groundDrop = 1.784,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 3.084 },
            { name = "LeftDoor", door = 2, x = -1.14, y = 1.558 },
            { name = "RightDoor", door = 3, x = 1.14, y = 1.56 },
            { name = "FrontBumper", panel = 5, x = 0, y = 4.809 },
        },
    },
    [528] = {
        prefix = "FbiTruck",
        groundDrop = 0.835,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.463 },
            { name = "LeftDoor", door = 2, x = -1.04, y = 0.107 },
            { name = "RightDoor", door = 3, x = 1.04, y = 0.107 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.558 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.544 },
        },
    },
    [542] = {
        prefix = "Clover",
        groundDrop = 0.543,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.503 },
            { name = "Trunk", door = 1, x = 0, y = -2.722 },
            { name = "LeftDoor", door = 2, x = -1.1, y = 0.02 },
            { name = "RightDoor", door = 3, x = 1.1, y = 0.02 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.641 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.798 },
        },
    },
    [543] = {
        prefix = "Sadler",
        groundDrop = 0.6,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.397 },
            { name = "Tailgate", door = 1, x = 0, y = -2.398 },
            { name = "LeftDoor", door = 2, x = -1.189, y = 0.279 },
            { name = "RightDoor", door = 3, x = 1.189, y = 0.279 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.19 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.489 },
        },
    },
    [549] = {
        prefix = "Tampa",
        groundDrop = 0.501,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.661 },
            { name = "Trunk", door = 1, x = 0, y = -2.3 },
            { name = "LeftDoor", door = 2, x = -1.001, y = 0.398 },
            { name = "RightDoor", door = 3, x = 1, y = 0.397 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.515 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.412 },
        },
    },
    [554] = {
        prefix = "Yosemite",
        groundDrop = 0.795,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.624 },
            { name = "Tailgate", door = 1, x = 0, y = -2.617 },
            { name = "LeftDoor", door = 2, x = -1.221, y = 0.332 },
            { name = "RightDoor", door = 3, x = 1.221, y = 0.332 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.555 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.796 },
        },
    },
    [560] = {
        prefix = "Sultan",
        groundDrop = 0.405,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.561 },
            { name = "Trunk", door = 1, x = 0, y = -2.1 },
            { name = "LeftDoor", door = 2, x = -1.108, y = 0.346 },
            { name = "RightDoor", door = 3, x = 1.109, y = 0.346 },
            { name = "RearLeftDoor", door = 4, x = -0.949, y = -0.791 },
            { name = "RearRightDoor", door = 5, x = 0.949, y = -0.791 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.552 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.235 },
        },
    },
    [573] = {
        prefix = "Dune",
        groundDrop = 1.3,
        slots = {
            { name = "LeftDoor", door = 2, x = -0.996, y = 2.129 },
            { name = "RightDoor", door = 3, x = 0.996, y = 2.129 },
            { name = "FrontBumper", panel = 5, x = 0, y = 3.046 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.976 },
        },
    },
    [578] = {
        prefix = "Dft30",
        groundDrop = 1.3,
        slots = {
            { name = "LeftDoor", door = 2, x = -1.62, y = 3.768 },
            { name = "RightDoor", door = 3, x = 1.62, y = 3.768 },
            { name = "FrontBumper", panel = 5, x = 0, y = 4.369 },
        },
    },
    [579] = {
        prefix = "Huntley",
        groundDrop = 0.689,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.374 },
            { name = "Trunk", door = 1, x = 0, y = -2.573 },
            { name = "LeftDoor", door = 2, x = -1.124, y = 0.12 },
            { name = "RightDoor", door = 3, x = 1.123, y = 0.12 },
            { name = "RearLeftDoor", door = 4, x = -1.006, y = -1.051 },
            { name = "RearRightDoor", door = 5, x = 1.005, y = -1.051 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.36 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.69 },
        },
    },
    [596] = {
        prefix = "Police",
        groundDrop = 0.5,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.494 },
            { name = "Trunk", door = 1, x = 0, y = -2.497 },
            { name = "LeftDoor", door = 2, x = -1.169, y = 0.337 },
            { name = "RightDoor", door = 3, x = 1.169, y = 0.337 },
            { name = "RearLeftDoor", door = 4, x = -0.99, y = -0.795 },
            { name = "RearRightDoor", door = 5, x = 0.99, y = -0.795 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.414 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.687 },
        },
    },
    [597] = {
        prefix = "Police",
        groundDrop = 0.5,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.494 },
            { name = "Trunk", door = 1, x = 0, y = -2.497 },
            { name = "LeftDoor", door = 2, x = -1.169, y = 0.337 },
            { name = "RightDoor", door = 3, x = 1.169, y = 0.337 },
            { name = "RearLeftDoor", door = 4, x = -0.99, y = -0.795 },
            { name = "RearRightDoor", door = 5, x = 0.99, y = -0.795 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.414 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.687 },
        },
    },
    [598] = {
        prefix = "PoliceLv",
        groundDrop = 0.5,
        slots = {
            { name = "Hood", door = 0, x = 0, y = 1.477 },
            { name = "Trunk", door = 1, x = 0, y = -2.452 },
            { name = "LeftDoor", door = 2, x = -1.19, y = 0.286 },
            { name = "RightDoor", door = 3, x = 1.19, y = 0.286 },
            { name = "RearLeftDoor", door = 4, x = -0.98, y = -0.896 },
            { name = "RearRightDoor", door = 5, x = 0.979, y = -0.896 },
            { name = "FrontBumper", panel = 5, x = 0, y = 2.427 },
            { name = "RearBumper", panel = 6, x = 0, y = -2.596 },
        },
    },
}

local byUname = {} -- part uname -> { good, models = { [model] = slot } }
for model, def in pairs(M.MODELS) do
    for _, slot in ipairs(def.slots) do
        slot.missing = slot.door and M.DOOR_MISSING or M.PANEL_MISSING
        if slot.door == 0 then
            slot.path = "$.hood"
        elseif slot.door == 1 then
            slot.path = "$.tailgate"
        elseif slot.door then
            slot.path = string.format("$.doors[%d]", slot.door - 2)
        else
            slot.path = string.format("$.panels[%d]", slot.panel)
        end
        for _, good in ipairs({ true, false }) do
            local uname = def.prefix .. slot.name .. (good and "Good" or "Bad")
            local p = byUname[uname] or { good = good, models = {} }
            p.models[model] = slot
            byUname[uname] = p
        end
    end
end

-- the item `uname` is a body part of some model
function M.isPart(uname)
    return byUname[uname] ~= nil
end

-- the slot of `model` the part item `uname` fills and whether the part is Good; nil when it does not fit that model
function M.slotFor(uname, model)
    local p = byUname[uname]
    local slot = p and p.models[model]
    if slot then
        return slot, p.good
    end
    return nil
end

-- the item a slot yields: Good while it is intact or only dented, Bad once it hangs broken
function M.uname(model, slot, good)
    return M.MODELS[model].prefix .. slot.name .. (good and "Good" or "Bad")
end

-- "missing" | "bad" | "good" for a slot in MTA state `state`
function M.condition(slot, state)
    if state == nil or state == false then
        return "missing"
    end
    if state >= slot.missing then
        return "missing"
    end
    return state >= 2 and "bad" or "good"
end

-- the state a freshly fitted part leaves the slot in
function M.installState(good)
    return good and 0 or 2
end

-- the slot of `model` nearest to the local point (lx, ly) within REACH, or nil
function M.nearestSlot(model, lx, ly)
    local def = M.MODELS[model]
    if not def then
        return nil
    end
    local best, bestD = nil, M.REACH * M.REACH
    for _, slot in ipairs(def.slots) do
        local d = (lx - slot.x) ^ 2 + (ly - slot.y) ^ 2
        if d <= bestD then
            best, bestD = slot, d
        end
    end
    return best
end

-- A part fitted by hand sits loose until a Ratchet secures it: driving shakes it off. Above LOOSE_KMH it comes off with
-- a chance per second that grows with speed; braking hard (LOOSE_BRAKE_KMH lost within a second) throws off every one.
M.LOOSE_KMH = 15
M.LOOSE_BRAKE_KMH = 25
M.LOOSE_FULL_KMH = 75 -- from here a loose part is shaken off almost at once

-- kmh: speed now, lastKmh: speed a second ago, roll: a random number in [0, 1); returns "all" | "one" | nil
function M.comesOff(kmh, lastKmh, roll)
    if (lastKmh or 0) - kmh >= M.LOOSE_BRAKE_KMH then
        return "all"
    end
    if kmh <= M.LOOSE_KMH then
        return nil
    end
    local chance = math.min(0.9, (kmh - M.LOOSE_KMH) / (M.LOOSE_FULL_KMH - M.LOOSE_KMH))
    if roll < chance then
        return "one"
    end
    return nil
end

-- where a detached part lands, in the vehicle's local frame (a little outside its slot)
function M.dropPoint(slot)
    return slot.x * 1.4, slot.y * 1.1
end

return M
