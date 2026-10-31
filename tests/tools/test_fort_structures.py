from tools import fort_structures as st
from tools import make_fort_kit as kit
from tools.convert import maps


def test_the_lab_deck_has_its_top_at_the_origin_and_posts_to_the_ground():
    parts, cols = st.piece("fort_labdeck")
    assert all(p[6] in kit.TEXTURES for p in parts)
    posts = [c for c in cols if c[3] < 1.0]
    assert len(posts) >= 3 and all(p[2] + p[5] / 2 < -0.1 for p in posts)  # posts hang from under the deck
    deck = [c for c in cols if c[3] >= 1.0]
    assert deck and all(abs(c[2] + 0.07) < 0.001 for c in deck)  # every slab is a plank deck topped at the origin
    assert max(c[2] + c[5] / 2 for c in cols) <= 0.001  # nothing stands above the deck's top


def test_the_shelter_keeps_the_barns_footprint_and_has_a_gable_roof():
    parts, cols = st.piece("fort_shelter")
    roofs = [p for p in parts if len(p) > 7 and p[6] == st.SHEET]
    assert len(roofs) == 2 and roofs[0][7] == -roofs[1][7] != 0
    xs = [p[0] for p in parts if p[6] == st.TIMBER and p[5] == 3.3]
    assert min(xs) == -6.8 and max(xs) == 6.8 and len(xs) == 10


def test_placements_stand_the_structures_where_upstream_had_theirs():
    ids = kit.model_ids()
    rows = st.placements(ids)
    assert {r[0] for r in rows} == {ids["fort_labdeck"], ids["fort_shelter"], ids["fort_leanto"]}
    by_id = {r[0]: r for r in rows}
    assert by_id[ids["fort_shelter"]][1:4] == [2484.079, -1664.151, 12.31]


def test_the_converter_adds_every_port_row_and_drops_the_replaced_models():
    rows = maps.port_rows("LS/Fort Defiance.map")
    ids = set(kit.model_ids().values())
    assert len(rows) == 8 + 3 and all(r[0] in ids for r in rows)
    assert maps.port_rows("LS/Houses.map") == []
    assert {3095, 17010, 16405, 3260} <= maps.REPLACED_MODELS["LS/Fort Defiance.map"]
