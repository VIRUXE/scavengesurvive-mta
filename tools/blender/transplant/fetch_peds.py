"""fetch_peds.py <work dir>: every ped of data/peds.ide (DFF and TXD) out of gta3.img into <work>/peds, and
<work>/list.txt (id,dff,txd,type), for the cranium transplant (README.md). Needs the GTA:SA install from the registry
or --gta."""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from tools.extract_samp_models import detect_gta, read_img_entry, read_img_index  # noqa: E402


def read_peds_ide(path: Path) -> list[tuple[int, str, str, str]]:
    rows, inside = [], False
    for line in path.read_text(errors="ignore").splitlines():
        line = line.split("#")[0].strip()
        if line == "peds":
            inside = True
        elif line == "end":
            inside = False
        elif inside and line:
            f = [x.strip() for x in line.split(",")]
            rows.append((int(f[0]), f[1].lower(), f[2].lower(), f[3]))
    return rows


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("work", type=Path)
    ap.add_argument("--gta", type=Path, help="GTA:SA folder (default: from the registry)")
    args = ap.parse_args(argv)
    gta = args.gta or detect_gta()
    img = gta / "models" / "gta3.img"
    index = read_img_index(img)
    out = args.work / "peds"
    out.mkdir(parents=True, exist_ok=True)
    rows = []
    for mid, dff, txd, typ in read_peds_ide(gta / "data" / "peds.ide"):
        if f"{dff}.dff" not in index or f"{txd}.txd" not in index:
            continue
        for entry in (f"{dff}.dff", f"{txd}.txd"):
            (out / entry).write_bytes(read_img_entry(img, index[entry]))
        rows.append(f"{mid},{dff},{txd},{typ}")
    (args.work / "list.txt").write_text("\n".join(rows) + "\n")
    print(f"{len(rows)} peds -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
