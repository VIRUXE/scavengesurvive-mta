import math
from pathlib import Path

import numpy as np
import pytest

from tools import extract_ped_models as peds
from tools import extract_samp_models as objects
from tools import hatless_proj as hp
from tools import hatless_rebuild as rebuild
from tools.port_hats import HATS


@pytest.mark.parametrize("view", sorted(hp.CAMERAS))
def test_camera_looks_at_ped_with_orthonormal_basis(view: str) -> None:
    c, fwd, right, up = hp.camera(view)
    look = hp.PED + np.array([0, 0, hp.CAMERAS[view][3]])
    dist = np.linalg.norm(look - c)
    assert np.allclose(c + fwd * dist, look)
    for v in (fwd, right, up):
        assert np.isclose(np.linalg.norm(v), 1.0)
    assert np.isclose(fwd @ right, 0) and np.isclose(fwd @ up, 0) and np.isclose(right @ up, 0)
    assert up[2] > 0


def test_front_camera_sits_at_positive_y() -> None:
    c, fwd, _, _ = hp.camera("front")
    assert c[1] > hp.PED[1] and np.isclose(c[0], hp.PED[0])
    assert fwd[1] < 0


def test_focal_from_70_degree_fov() -> None:
    assert math.isclose(hp.FOCAL, 960 / math.tan(math.radians(35)))


@pytest.mark.parametrize("view", sorted(hp.CAMERAS))
def test_to_shot_look_point_is_centre(view: str) -> None:
    look = hp.PED + np.array([0, 0, hp.CAMERAS[view][3]])
    assert np.allclose(hp.to_shot(view, [look])[0], (640, 480))


def test_to_shot_right_and_scale() -> None:
    c, fwd, right, up = hp.camera("front")
    p = c + fwd * 2.0
    x0, y0 = hp.to_shot("front", [p])[0]
    x1, y1 = hp.to_shot("front", [p + right * 0.1])[0]
    assert x1 > x0 and np.isclose(y1, y0)
    assert np.isclose(x1 - x0, hp.FOCAL * 0.1 / 2.0 * 1280 / 1920)
    x2, y2 = hp.to_shot("front", [p + up * 0.1])[0]
    assert y2 < y0 and np.isclose(y0 - y2, hp.FOCAL * 0.1 / 2.0 * 960 / 1080)


def test_cell_origin() -> None:
    assert hp.cell_origin("level", "front") == (0, 0)
    assert hp.cell_origin("level", "three") == (512, 0)
    assert hp.cell_origin("level", "side") == (0, 512)
    assert hp.cell_origin("top", "side") == (512, 512)


def test_to_grid_crops_and_scales() -> None:
    out = hp.to_grid("level", "front", [[340, 0], [940, 600]])
    assert np.allclose(out, [[0, 0], [512, 512]])
    out = hp.to_grid("level", "back", [[340, 0]], offset=(3, -2))
    assert np.allclose(out, [[512 + 3, 512 - 2]])
    top = hp.to_grid("top", "top", [[640, 140 + 300]])
    assert np.allclose(top, [[256, 256]])
    topback = hp.to_grid("top", "topback", [[340, 40]])
    assert np.allclose(topback, [[512, 0]])


def test_to_reference_identity_and_scale_about_cell_centre() -> None:
    xy = np.array([[600.0, 100.0], [520.0, 530.0]])
    assert np.allclose(hp.to_reference("level", "three", xy), xy)
    centre = np.array([[512 + 256, 256]])
    assert np.allclose(hp.to_reference("level", "three", centre, (2.0, 0, 0)), centre)
    p = np.array([[512 + 266, 256 + 10]])
    assert np.allclose(hp.to_reference("level", "three", p, (2.0, 0, 0)), [[512 + 276, 256 + 20]])
    assert np.allclose(hp.to_reference("level", "three", centre, (1.0, 5, -7)), [[512 + 256 + 5, 256 - 7]])


def test_to_world_rows_are_axes_then_position() -> None:
    m = np.eye(4)
    m[3, :3] = [10, 20, 30]
    assert np.allclose(hp.to_world(m, [[1, 2, 3]]), [[11, 22, 33]])
    rot = np.array([[0, 1, 0], [-1, 0, 0], [0, 0, 1.0]])
    m[:3, :3] = rot
    assert np.allclose(hp.to_world(m, [[1, 0, 0]]), [[10, 21, 30]])


def test_render_peds_writes_txd_only_for_listed(tmp_path: Path) -> None:
    text = peds.render_peds({37: "wmygol2_nohat", 4: "sfpdm1_nohat"}, {"wmygol2_nohat"})
    assert '[37] = { dff = "wmygol2_nohat", txd = "wmygol2_nohat" },' in text
    assert '[4] = { dff = "sfpdm1_nohat" },' in text
    assert text.count("txd =") == 1
    (tmp_path / "peds.lua").write_text(text, encoding="ascii")
    assert peds.read_peds(tmp_path / "peds.lua") == {4: "sfpdm1_nohat", 37: "wmygol2_nohat"}


def test_ped_files_lists_dffs_and_txds(tmp_path: Path) -> None:
    (tmp_path / "peds.lua").write_text(peds.render_peds({37: "wmygol2_nohat", 4: "sfpdm1_nohat"}, {"wmygol2_nohat"}), encoding="ascii")
    assert objects.ped_files(tmp_path) == ["sfpdm1_nohat.dff", "wmygol2_nohat.dff", "wmygol2_nohat.txd"]
    assert objects.ped_files(tmp_path / "none") == []


def test_listed_blocks() -> None:
    pilot = next(h for h in HATS if h["skin"] == 61)
    assert set(pilot["blocks"]) <= set(rebuild.listed_blocks(61))
    assert rebuild.listed_blocks(61) == sorted(pilot["blocks"])
    assert {(3, 7), (4, 7), (5, 7), (6, 7), (7, 7)} <= set(rebuild.listed_blocks(4))
    assert not any(h["skin"] == 37 for h in HATS)
    assert rebuild.listed_blocks(37) == []


def test_planes_are_sane() -> None:
    for skin, plane in rebuild.PLANES.items():
        assert skin in peds.HEADGEAR
        assert 0 < plane["front"] < 0.2 and 0 < plane["back"] < 0.2


def test_every_headgear_skin_players_can_get_has_a_rebuilt_bare_head():
    # spawn rolls and Clothes items draw from items/shared/logic/clothes.lua TYPES; a headgear skin there must have a
    # rebuilt twin (a PLANES row), which players always see instead of the hatted skin (items attach.lua, #89)
    import re
    from pathlib import Path

    from tools.extract_ped_models import HEADGEAR
    from tools.hatless_rebuild import PLANES

    src = (Path(__file__).resolve().parents[2] / "resources" / "[scavengesurvive]" / "items" / "shared" / "logic" / "clothes.lua").read_text(encoding="utf8")
    pool = {int(m) for m in re.findall(r"^\s*\{ (\d+), \"", src, re.M)}
    assert pool, "no clothes types parsed"
    assert sorted(s for s in pool & set(HEADGEAR) if s not in PLANES) == []
