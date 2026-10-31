"""The Rockstar placements of the game copy: every INST row of the text IPLs and the binary stream IPLs in gta3.img."""
from __future__ import annotations

import struct
from pathlib import Path

from tools.extract_samp_models import read_img_entry, read_img_index


def quat_matrix(qx: float, qy: float, qz: float, qw: float) -> list[list[float]]:
    """Rotation matrix of an IPL quaternion; IPLs store the inverse, so the vector part is negated first."""
    qx, qy, qz = -qx, -qy, -qz
    return [
        [1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy - qz * qw), 2 * (qx * qz + qy * qw)],
        [2 * (qx * qy + qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz - qx * qw)],
        [2 * (qx * qz - qy * qw), 2 * (qy * qz + qx * qw), 1 - 2 * (qx * qx + qy * qy)],
    ]


def native_instances(gta: Path) -> list[tuple[int, tuple[float, float, float], list[list[float]]]]:
    """(model, position, rotation matrix) of every vanilla placement: text IPLs plus the binary stream IPLs in gta3.img."""
    found = []
    for ipl in (gta / "data" / "maps").rglob("*.ipl"):
        section = None
        for line in ipl.read_text(errors="ignore").splitlines():
            line = line.split("#")[0].strip()
            low = line.lower()
            if low in ("inst", "cull", "grge", "enex", "pick", "jump", "tcyc", "auzo", "mult", "cars", "occl", "zone", "path"):
                section = low
            elif low == "end":
                section = None
            elif section == "inst" and line:
                p = [s.strip() for s in line.split(",")]
                if len(p) >= 10 and int(p[2]) == 0:
                    found.append((int(p[0]), (float(p[3]), float(p[4]), float(p[5])), quat_matrix(*(float(v) for v in p[6:10]))))
    img = gta / "models" / "gta3.img"
    for name, where in read_img_index(img).items():
        blob = read_img_entry(img, where)
        if not name.endswith(".ipl") or blob[:4] != b"bnry":
            continue
        count, at = struct.unpack_from("<I", blob, 4)[0], struct.unpack_from("<I", blob, 0x1C)[0]
        for k in range(count):
            x, y, z, qx, qy, qz, qw, model = struct.unpack_from("<7fi", blob, at + k * 40)
            found.append((model, (x, y, z), quat_matrix(qx, qy, qz, qw)))
    return found
