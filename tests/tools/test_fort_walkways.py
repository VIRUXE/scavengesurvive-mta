import math

from pytest import approx

from tools import fort_walkways as w
from tools import make_fort_kit as kit


def test_a_span_runs_from_its_start_to_its_end_and_is_turned_toward_the_end():
    spec = w.layout("fort_walk_n_ramp")
    (x0, y0, z0), (x1, y1, z1) = spec["a"], spec["b"]
    assert round(spec["length"], 3) == round(math.hypot(x1 - x0, y1 - y0), 3) and round(spec["dz"], 3) == round(z1 - z0, 3)
    # the model runs along its local +y; turned by `heading` that axis points at the end
    h = math.radians(spec["heading"])
    assert math.isclose(-math.sin(h), (x1 - x0) / spec["length"], abs_tol=1e-6) and math.isclose(math.cos(h), (y1 - y0) / spec["length"], abs_tol=1e-6)


def test_every_span_joins_a_neighbour_or_a_roof_and_stays_inside_the_fort():
    for name, (_kind, a, b, _floors) in w.SPANS.items():
        for x, y, z in (a, b):
            assert 2480 < x < 2540 and -1700 < y < -1625 and 12 < z < 20, name


def test_the_decks_rise_with_the_measured_heights_and_collision_follows_them():
    for name in w.SPANS:
        spec = w.layout(name)
        parts, cols = w.piece(name)
        assert parts and cols and all(p[6] in kit.TEXTURES for p in parts), name
        tops = [c[2] + c[5] / 2 for c in cols if c[3] > 1.0]  # the deck/tread boxes, not the rails
        assert min(tops) <= 0.4 and max(tops) >= spec["dz"] - 0.3, name


def test_stairs_have_walkable_risers():
    spec = w.layout("fort_walk_e_stairs")
    _parts, cols = w.piece("fort_walk_e_stairs")
    treads = sorted((c for c in cols if c[3] > 1.0), key=lambda c: c[1])
    rises = [b[2] + b[5] / 2 - (a[2] + a[5] / 2) for a, b in zip(treads, treads[1:])]
    assert rises and max(rises) <= 0.3 and spec["kind"] == "stairs"


def test_supports_reach_the_floor_over_a_gap_but_not_where_the_deck_lies_on_a_roof():
    spec = w.layout("fort_walk_n_bridge")
    posts = w.supports(spec)
    assert posts and any(p[5] > 3.0 for p in posts)  # tall posts down to the grass in the gap
    assert all(p[1] > 6.0 or p[5] < 1.8 for p in posts)  # near the ends the deck is a metre or so above the roof


def test_placements_stand_each_span_at_its_start_with_its_model_id():
    ids = kit.model_ids()
    rows = w.placements(ids)
    assert len(rows) == len(w.SPANS) and all(len(r) == 10 for r in rows)
    assert {r[0] for r in rows} == {ids[n] for n in w.SPANS}
    assert [r[1:4] for r in rows][0] == list(w.SPANS["fort_walk_n_stairs"][1])


def test_a_bridge_is_lifted_over_a_roof_that_would_reach_it(monkeypatch):
    spec_a, spec_b = (0.0, 0.0, 17.0), (0.0, 4.0, 17.0)
    samples = [{"s": float(s), "top": [None, 16.0, 17.5 if s == 2 else 16.0, 16.0, None], "floor": [12.5] * 5} for s in range(5)]
    monkeypatch.setattr(w, "surfaces", lambda: {"fort_walk_n_bridge": samples})
    nodes = w.fitted_nodes("fort_walk_n_bridge", spec_a, 0.0, 4.0)
    assert max(z for _s, z in nodes) == approx(17.5 + w.CLEAR - 17.0)
    assert nodes[0][0] == 0.0 and nodes[-1][0] == 4.0
    assert spec_b[2] == spec_a[2]
