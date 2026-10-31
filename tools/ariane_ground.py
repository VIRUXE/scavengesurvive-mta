"""Ground heights from the running Ariane editor, for tools that lay props out on the real terrain.

    <ariane-agent venv python> tools/ariane_ground.py '[[x, y], ...]' [top] [bottom]

Casts a ray straight down at each point from `top` (default 16) to `bottom` (default 8) through ARIANE_ENGINE_TCP_PORT /
ARIANE_ENGINE_TOKEN (what samp-house-shells/ariane/ctl.ps1 sets) and prints a JSON list: the z of the first hit, or null
where nothing was hit. Run it with the agent venv's Python, which has ariane_agent_tools; tools/fort_layout.py does.
"""
import json
import sys

from ariane_agent_tools.ariane_ipc import ArianeClient


def main() -> int:
    points = json.loads(sys.argv[1])
    top = float(sys.argv[2]) if len(sys.argv) > 2 else 16.0
    bottom = float(sys.argv[3]) if len(sys.argv) > 3 else 8.0
    client = ArianeClient()
    heights = []
    for x, y in points:
        hit = (client.command("raycast_segment", x, y, top, x, y, bottom).get("ray") or {}).get("hit")
        heights.append(round(hit["point"][2], 3) if hit else None)
    print(json.dumps(heights))
    return 0


if __name__ == "__main__":
    sys.exit(main())
