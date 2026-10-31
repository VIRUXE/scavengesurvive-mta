from tools import fort_spans as sp


def test_the_long_axis_of_a_prop_tipped_onto_its_side_is_taken_along_the_ground():
    # a 1 x 1 x 6 m post lying on its side (ry 90): its long local axis (z) now runs along x
    a, b, length, width = sp.axis_line([1, 100, 200, 10, 0, 90, 0], (-0.5, -0.5, -3.0, 0.5, 0.5, 3.0))
    assert round(length, 2) == 6.0 and round(abs(b[0] - a[0]), 2) == 6.0 and round(abs(b[1] - a[1]), 2) == 0.0


def test_samples_walk_the_axis_every_half_metre_up_to_a_cap():
    pts, step = sp.sample_points((0, 0, 0), (10, 0, 0), 10.0)
    assert len(pts) == 21 and step == 0.5 and pts[-1] == (10.0, 0.0)
    pts, step = sp.sample_points((0, 0, 0), (100, 0, 0), 100.0)
    assert len(pts) == sp.MAX_SAMPLES + 1 and step > 0.5


def test_runs_merge_samples_on_the_same_surface_and_keep_gaps():
    roof, ground = {"z": 17.2, "name": "roof"}, {"z": 12.5, "name": "grass"}
    out = sp.runs([roof, {"z": 17.3, "name": "roof"}, ground, ground, None, roof], 0.5)
    assert [(r[0], r[1], r[2]) for r in out] == [(0.0, 0.5, 17.2), (1.0, 1.5, 12.5), (2.0, 2.0, None), (2.5, 2.5, 17.2)]


def test_measure_flags_a_duplicated_row_and_skips_unknown_models():
    names = {3406: ("jetty", "t"), 9: ("other", "t")}
    bounds = {"dff": {"jetty": (-4.0, -1.0, 0.0, 4.0, 1.0, 3.0)}, "col": {}}
    rows = [[3406, 10, 10, 5, 0, 0, 0, -1, -1, 350.0]] * 2 + [[9, 0, 0, 0, 0, 0, 0, -1, -1, 350.0]]
    out = sp.measure(rows, names, bounds, profile=lambda pts, skipped: [{"z": 12.5, "model": 1, "name": "ground"} for _ in pts])
    assert [o["dup"] for o in out] == [False, True] and {o["name"] for o in out} == {"jetty"}
    assert out[0]["runs"][0][2] == 12.5
