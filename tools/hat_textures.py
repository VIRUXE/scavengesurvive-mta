"""Build the head-slot items' game dictionaries from their UV-mapped artwork.

    python -m tools.hat_textures

Each source directory names its output dictionary. The PNG inside keeps the
texture name requested by the original mesh, including for the hats cut from
character atlases. All hats use opaque BC1 with a full trilinear mip chain.
"""
from pathlib import Path

from PIL import Image

from tools.make_vending import write_txd
from tools.port_hats import HATS, SAMP_HAT_TEXTURES
from tools.wheel_hd import native_dxt1

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools" / "data" / "hat_textures"
RESOURCES = ROOT / "resources" / "[scavengesurvive]"


def build_dictionary(files: Path, name: str) -> None:
    source, = (SOURCE / name).glob("*.png")
    with Image.open(source) as image:
        if image.mode != "RGB" or any(size & (size - 1) for size in image.size):
            raise ValueError(f"{source} must be an opaque RGB texture with power-of-two dimensions")
        write_txd(files / f"{name}.txd", [native_dxt1(source.stem, image)])


def main():
    for name in SAMP_HAT_TEXTURES.values():
        build_dictionary(RESOURCES / "samp_models" / "files", name)
    for hat in HATS:
        build_dictionary(RESOURCES / "hat_models" / "files", hat["dff"])


if __name__ == "__main__":
    main()
