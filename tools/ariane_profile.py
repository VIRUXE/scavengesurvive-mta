"""Surface heights under points from the running Ariane editor, looking past the models you name.

    <ariane-agent venv python> tools/ariane_profile.py '[[x, y], ...]' '[skipped model ids]' [top] [bottom]

For each point it casts a ray straight down from `top` (default 45) to `bottom` (default 5); a hit on a skipped model
(the fort's own props) is stepped past and the ray continues below it, so what is reported is the first surface of
anything else: a roof, a wall, the ground. Prints a JSON list of {"z", "model", "name"} or null per point. Needs
ARIANE_ENGINE_TCP_PORT / ARIANE_ENGINE_TOKEN like tools/ariane_ground.py.
"""
import json
import sys

from ariane_agent_tools.ariane_ipc import ArianeClient

STEP = 0.02
MAX_SKIPS = 12


def surface(client, x, y, skipped, top, bottom):
    z = top
    for _ in range(MAX_SKIPS):
        hit = (client.command("raycast_segment", x, y, z, x, y, bottom).get("ray") or {}).get("hit")
        if not hit:
            return None
        if hit["model_id"] not in skipped:
            return {"z": round(hit["point"][2], 2), "model": hit["model_id"], "name": hit["name"]}
        z = hit["point"][2] - STEP
    return None


def main() -> int:
    points, skipped = json.loads(sys.argv[1]), set(json.loads(sys.argv[2]))
    top = float(sys.argv[3]) if len(sys.argv) > 3 else 45.0
    bottom = float(sys.argv[4]) if len(sys.argv) > 4 else 5.0
    client = ArianeClient()
    print(json.dumps([surface(client, x, y, skipped, top, bottom) for x, y in points]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
