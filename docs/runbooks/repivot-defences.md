# Re-pivoted defence doors

Three defence items are drawn from vanilla GTA doors whose pivot is their hinge: MetPanel (1965), CrateDoor (3062)
and ShipDoor (2944). The port gives each one a copy moved onto the middle of its footprint under a port-only model id
(#149). Interact reach, the "behind" test, the tweak arrow and the tweak's turns then work from the middle of the door.
A door built from a lying item still stands exactly where upstream's did.

| Item | Vanilla | Port id | Files (`models/files/`) | pivot (m, model space) |
| --- | --- | --- | --- | --- |
| MetPanel | 1965 `imcmptrkdrl_las` (gta_int.img) | 20301 | `imcmptrkdrl_las_def.dff/.col` | 0.0078125, 0.734375, 0 |
| CrateDoor | 3062 `container_door` (gta3.img) | 20302 | `container_door_def.dff/.col` | 0.7890625, -0.0234375, 0 |
| ShipDoor | 2944 `freight_sfw_door` (gta3.img) | 20303 | `freight_sfw_door_def.dff/.col` | -0.0546875, -0.7109375, 0 |

## Pieces

- `tools/port_defences.py`: the table. Each pivot is the x/y centre of the vanilla mesh's bounds, rounded to 1/128 m
  so the COL's fixed-point vertices shift exactly. z stays 0, because the doors are already centred on their height
  and upstream's `zOffset` raises them from there.
- `tools/repivot_defences.py`: run in Blender with DragonFF (`blender -b --python tools/repivot_defences.py --
  [GTA_DIR]`). It takes each DFF out of its IMG and moves the mesh by -pivot. It moves the vanilla COL (from
  `levelxre.col` / `props.col`) the same way: bounds, spheres, boxes, face groups, and mesh and shadow vertices. It
  writes `models/defences.lua` (`txdModel` and `parent` = the vanilla id, so the copy keeps its TXD and object.dat
  physical properties group) and rewrites `models/meta.xml`. If a measured centre is more than 1/256 m from the table,
  it stops and prints the value to use.
- `tools/convert/item_types.py` `apply_port_defences`: points the item type at the port id, puts the pivot in its
  `defence`, and moves the held bone offset (`attx/y/z`) by the pivot, turned as `items/client/attach.lua` turns the
  object, so the door stays where it was in the hand. `data/model_map.lua` falls back to the vanilla id while
  `models` is not running.
- `building/shared/logic/defences.lua` `pivotOffset` = R·pivot, with MTA's object rotation R = Rz·Rx·Ry (checked
  against `getElementMatrix`). `build` stores the hinge plus that offset, `unbuild` takes it off again, and `toggle`
  turns about the hinge, as upstream does, then re-applies the offset for the new pose.

A lying (unbuilt) door is now drawn centred on its item position instead of hinged there. Nothing compensates for
this, because the drop spot is where the player stands.

## Deploying

1. `rr models` (new files, `defences.lua`), then `rr data` (item types, model map), then `rr items` and
   `rr building`.
2. Built rows from before the change store hinge positions. Move them once, in the same session as the deploy,
   before anyone unbuilds or toggles one (`defence.active` is `1` from `JSON_VALUE`, not `'true'`):

```sql
UPDATE items i
JOIN (SELECT 'MetPanel' AS u, 0.0078125 AS px, 0.734375 AS py UNION ALL SELECT 'CrateDoor', 0.7890625, -0.0234375 UNION ALL SELECT 'ShipDoor', -0.0546875, -0.7109375) p ON p.u = i.type_uname
JOIN (SELECT id, RADIANS(COALESCE(JSON_VALUE(data, '$.defence.rx'), JSON_VALUE(data, '$[0].defence.rx'))) AS a, RADIANS(COALESCE(JSON_VALUE(data, '$.defence.ry'), JSON_VALUE(data, '$[0].defence.ry'))) AS b, RADIANS(rz) AS c FROM items WHERE type_uname IN ('MetPanel', 'CrateDoor', 'ShipDoor') AND x IS NOT NULL AND COALESCE(JSON_VALUE(data, '$.defence.active'), JSON_VALUE(data, '$[0].defence.active')) IN ('1', 'true')) r ON r.id = i.id
SET i.x = i.x + p.px * COS(r.b) * COS(r.c) - (p.py * COS(r.a) + p.px * SIN(r.b) * SIN(r.a)) * SIN(r.c),
    i.y = i.y + p.px * COS(r.b) * SIN(r.c) + (p.py * COS(r.a) + p.px * SIN(r.b) * SIN(r.a)) * COS(r.c),
    i.z = i.z + p.py * SIN(r.a) - p.px * SIN(r.b) * COS(r.a);
UPDATE item_types SET model = CASE uname WHEN 'MetPanel' THEN 20301 WHEN 'CrateDoor' THEN 20302 WHEN 'ShipDoor' THEN 20303 END WHERE uname IN ('MetPanel', 'CrateDoor', 'ShipDoor');
```

To add another hinged defence: add a row to `tools/port_defences.py`, run the Blender tool, run
`python -m tools.convert items`, then commit the files, `defences.lua`, `meta.xml` and `data/generated`.
