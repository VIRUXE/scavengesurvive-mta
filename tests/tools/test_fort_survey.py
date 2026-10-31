import struct

from tools import fort_survey as fs
from tools import model_bounds as mb


def _struct_chunk(verts: list[tuple[float, float, float]]) -> bytes:
    """A geometry struct for `verts`: no prelight, no UVs, one triangle, vertices present."""
    n = len(verts)
    body = struct.pack("<HBBiii", 0, 0, 0, 1, n, 1)
    body += struct.pack("<4HHH", 0, 1, 2, 0, 0, 0)[: 8 * 1]  # one triangle: 8 bytes
    body += struct.pack("<4f", 0, 0, 0, 1) + struct.pack("<ii", 1, 0)
    body += b"".join(struct.pack("<3f", *v) for v in verts)
    return body


def _rw(kind: int, body: bytes) -> bytes:
    return struct.pack("<III", kind, len(body), 0x36003) + body


def test_dff_box_reads_the_vertices_of_every_geometry():
    geo = _rw(mb.GEOMETRY, _rw(1, _struct_chunk([(-1, -2, 0), (3, 4, 5), (0, 0, 1)])))
    dff = _rw(mb.CLUMP, _rw(mb.GEOMETRY_LIST, _rw(1, b"\0" * 8) + geo))
    assert mb.dff_box(dff) == (-1.0, -2.0, 0.0, 3.0, 4.0, 5.0)


def test_col_models_split_chunks_and_flag_geometry():
    def col(name, box, shapes):
        body = name.encode().ljust(22, b"\0") + struct.pack("<H", 0) + struct.pack("<10f", *box, 0, 0, 0, 1)
        body += struct.pack("<HHH", *shapes) + b"\0" * 32
        return b"COL3" + struct.pack("<I", len(body)) + body

    models = mb.col_models(col("Wall", (0, 0, 0, 4, 1, 3), (0, 1, 0)) + col("Empty", (0, 0, 0, 1, 1, 1), (0, 0, 0)))
    assert models["wall"] == {"box": (0, 0, 0, 4, 1, 3), "has_geom": True}
    assert models["empty"]["has_geom"] is False


def test_world_box_turns_a_box_a_quarter_turn_about_z():
    box = fs.world_box((-2, -1, 0, 2, 1, 3), fs.matrix(0, 0, 90), (10, 20, 5))
    assert [round(v, 3) for v in box] == [9.0, 18.0, 5.0, 11.0, 22.0, 8.0]


def test_overlap_and_gap():
    a, b, c = (0, 0, 0, 2, 2, 2), (1, 1, 1, 3, 3, 3), (5, 0, 0, 6, 1, 1)
    assert fs.overlap(a, b) == 1.0 and fs.overlap(a, c) == 0.0
    assert fs.gap(a, b) == 0.0 and fs.gap(a, c) == 3.0


def test_clusters_link_boxes_within_the_gap():
    boxes = [(0, 0, 0, 1, 1, 1), (1.5, 0, 0, 2.5, 1, 1), (10, 10, 0, 11, 11, 1), (11.5, 10, 0, 12, 11, 1), (30, 0, 0, 31, 1, 1)]
    assert fs.clusters(boxes) == [[0, 1], [2, 3], [4]]


def test_survey_flags_a_prop_that_pokes_through_a_native():
    names = {1: ("post", "t"), 2: ("house", "t")}
    bounds = {"dff": {"post": (-0.5, -0.5, 0, 0.5, 0.5, 4), "house": (-5, -5, 0, 5, 5, 6)}, "col": {}}
    rows = [[1, 4.8, 0, 0, 0, 0, 0, -1, -1, 350.0], [1, 40, 0, 0, 0, 0, 0, -1, -1, 350.0]]
    natives = [(2, (0.0, 0.0, 0.0), fs.matrix(0, 0, 0))]
    groups = fs.survey(rows, names, bounds, natives)
    assert [g["protrudes"] for g in groups] == [["house"], []]
    assert groups[0]["role"] == "furniture/loot"
