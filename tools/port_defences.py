"""Defence items whose vanilla model is hinged at one edge, re-pivoted onto the middle of their footprint (#149).

Upstream builds a MetPanel, CrateDoor or ShipDoor out of a GTA door whose pivot is its hinge, so the item's position
(where interact reach, the "behind" test and the tweak arrow are measured from, and what the tweak turns about) sits
0.7-0.8 m off the middle of the door. The port gives each one a copy of the vanilla DFF and COL moved by -pivot, under
a port-only model id (tools/repivot_defences.py writes models/files/<dff>.dff/.col and models/defences.lua), and
building/shared/logic/defences.lua moves a built row by the rotated pivot, so a door built from the same lying item
stands exactly where upstream's did.

pivot is the footprint centre of the vanilla mesh in model space (x/y centre of its bounds), rounded to 1/128 m so
the COL's fixed-point vertices shift exactly; z stays 0, because the doors are already centred on their height and
upstream's zOffset raises them from that. The vanilla model stays the parent (object.dat physical properties group,
TXD), and the vanilla ids are never replaced: the maps place 1965 and the others as world objects.

The converters (tools/convert/item_types.py) point each item type at its copy and give its `defence` the pivot.
"""

DEFENCES = [
    {"uname": "MetPanel", "vanilla": 1965, "name": "imcmptrkdrl_las", "img": "gta_int.img", "col": "props.col", "model": 20301, "pivot": (0.0078125, 0.734375, 0.0)},
    {"uname": "CrateDoor", "vanilla": 3062, "name": "container_door", "img": "gta3.img", "col": "levelxre.col", "model": 20302, "pivot": (0.7890625, -0.0234375, 0.0)},
    {"uname": "ShipDoor", "vanilla": 2944, "name": "freight_sfw_door", "img": "gta3.img", "col": "levelxre.col", "model": 20303, "pivot": (-0.0546875, -0.7109375, 0.0)},
]
