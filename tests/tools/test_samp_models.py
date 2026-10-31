import struct

from tools import extract_samp_models as m


def _img(path, files):
    """Write a VER2 IMG with the given {name: bytes}; every entry is sector-aligned."""
    count = len(files)
    dir_size = 8 + 32 * count
    data_start = (dir_size + m.SECTOR - 1) // m.SECTOR * m.SECTOR
    entries, blobs, offset = [], [], data_start
    for name, blob in files.items():
        sectors = (len(blob) + m.SECTOR - 1) // m.SECTOR
        entries.append(struct.pack("<IHH24s", offset // m.SECTOR, sectors, 0, name.encode()))
        blobs.append(blob.ljust(sectors * m.SECTOR, b"\0"))
        offset += sectors * m.SECTOR
    path.write_bytes((b"VER2" + struct.pack("<I", count) + b"".join(entries)).ljust(data_start, b"\0") + b"".join(blobs))


IDE = """# comment
18633, GTASAWrench1, MatTextures, 100, 0
19554, Beanie1, ogloc, 100, 0
19581, MarcosFryingPan1, lee_kitch, 100, 0
19901, AnimTube, MatTextures, AnimTube, 299, 0
"""


def _col(name: str, payload: bytes = b"x" * 96) -> bytes:
    body = name.encode("latin1").ljust(22, b"\0") + struct.pack("<H", 0) + payload
    return b"COL3" + struct.pack("<I", len(body)) + body


def test_img_index_and_entry_round_trip(tmp_path):
    img = tmp_path / "SAMP.img"
    _img(img, {"GTASAWrench1.dff": b"wrench-dff", "MatTextures.txd": b"mat-txd" * 400})
    index = m.read_img_index(img)
    assert set(index) == {"gtasawrench1.dff", "mattextures.txd"}
    assert m.read_img_entry(img, index["gtasawrench1.dff"]).rstrip(b"\0") == b"wrench-dff"
    assert m.read_img_entry(img, index["mattextures.txd"]).rstrip(b"\0") == b"mat-txd" * 400


def test_parse_col_library_splits_concatenated_chunks():
    c1, c2 = _col("GTASAWrench1", b"a" * 96), _col("Beanie1", b"b" * 120)
    cols = m.parse_col_library(c1 + c2 + b"\0" * 500)
    assert cols == {"gtasawrench1": c1, "beanie1": c2}


def test_plan_picks_samp_txd_then_vanilla_owner_then_vanilla_archive():
    ide = m.parse_ide(IDE)
    assert ide[18633] == ("GTASAWrench1", "MatTextures", 100) and 19901 not in ide  # animated objects have 6 fields
    samp_index = {"gtasawrench1.dff": (0, 1), "mattextures.txd": (0, 1), "beanie1.dff": (0, 1),
                  "marcosfryingpan1.dff": (0, 1)}
    samp_cols = {"gtasawrench1": b"c1", "beanie1": b"c2", "marcosfryingpan1": b"c3"}
    owners = {"lee_kitch": 3961}
    used = m.models_used('M.byUname.Wrench = { model = 18633 }\nM.byUname.Beanie = { model = 19554, modelz = 0 }\n'
                         'M.byUname.Pan = { model = 19581 }\nM.byUname.Knife = { model = 335 }\n'
                         'M.byUname.Lost = { model = 19999 }')
    assert used == [335, 18633, 19554, 19581, 19999]
    entries, problems = m.plan(ide, used, samp_index, owners, {"gta3": {"ogloc.txd": (0, 1)}}, samp_cols=samp_cols)
    assert entries[18633]["txd"] == "mattextures" and entries[18633]["src"]["txd"] == ("samp", "mattextures.txd")
    assert entries[18633]["src"]["col"] == ("col", "gtasawrench1.col")
    assert entries[19581]["txdModel"] == 3961 and "txd" not in entries[19581]
    assert entries[19554]["txd"] == "ogloc" and entries[19554]["src"]["txd"] == ("gta3", "ogloc.txd")
    assert 335 not in entries and problems == ["19999: not in samp.ide"]
    manifest = m.render_manifest(entries)
    assert manifest.startswith(m.HEADER + "\nreturn {\n")
    assert '    [18633] = { dff = "gtasawrench1", txd = "mattextures", dist = 100 },' in manifest
    assert '    [19581] = { dff = "marcosfryingpan1", txdModel = 3961, dist = 100 },' in manifest
    meta = m.render_meta(entries)
    assert meta.count("<file src=\"files/") == 8
    assert '<file src="files/gtasawrench1.col"/>' in meta and '<file src="files/ogloc.txd"/>' in meta
    assert '<export function="resolve" type="client"/>' in meta
    assert m.render_manifest(entries) == manifest  # deterministic


def test_map_models_are_read_from_object_rows_only(tmp_path):
    lua = ("return {\n    objects = {\n        { 19312, 191.141, 1870.04, 21.4766, 0, 0, 0, -1, -1, 350.0 },\n"
           "        { 3168, 1.0, 2.0, 3.0, 0, 0, 0, -1, -1, 350.0 },\n    },\n    removals = {\n"
           "        { 16203, 199.344, 1943.79, 18.2031, 250.0 },\n    },\n    materials = {\n"
           '        { args = "objectid, 0, 5145", call = "SetObjectMaterial", object = 6 },\n    },\n}\n')
    # removals look the same as objects, so a vanilla removal id is harmless: plan() keeps SA-MP ids only
    assert m.map_models_used(lua) == [3168, 16203, 19312]
    items = tmp_path / "item_types.lua"
    items.write_text("M.byUname.Wrench = { model = 18633 }\n", encoding="utf-8")
    maps = tmp_path / "maps"
    maps.mkdir()
    (maps / "LS.lua").write_text(lua, encoding="utf-8")
    (maps / "index.lua").write_text("return { LS = { objects = 2, removals = 1 } }\n", encoding="utf-8")
    assert m.all_models_used(items, maps) == [3168, 11730, 16203, 18633, 18724, 19087, 19312, 19313, 19475, 19477, 19836]
    assert m.all_models_used(items, tmp_path / "missing") == [11730, 18633, 18724, 19087, 19313, 19475, 19477, 19836]


def test_port_hat_models_are_not_samp_models():
    assert all(m.is_samp_model(i) for i in (18631, 19999, 11682, 11753))
    assert not any(m.is_samp_model(i) for i in (20001, 18630, 11754))


def _rw(kind: int, body: bytes) -> bytes:
    return struct.pack("<III", kind, len(body), 0x1803FFFF) + body


def _native(name: str) -> bytes:
    return _rw(0x15, _rw(0x01, struct.pack("<II", 8, 0) + name.encode().ljust(32, b"\0") + b"\0" * 40) + _rw(0x03, b""))


def test_trim_txd_keeps_only_the_textures_the_model_names():
    txd = _rw(0x16, _rw(0x01, struct.pack("<HH", 2, 9)) + _native("bloodpool_64") + _native("smoke") + _rw(0x03, b""))
    dff = b"\0\0BloodPool1\0bloodpool_64\0"
    out = m.trim_txd(txd, m.dff_strings(dff))
    assert b"bloodpool_64" in out and b"smoke" not in out
    assert struct.unpack_from("<III", out, 0)[1] == len(out) - 12
    assert struct.unpack_from("<HH", out, 24) == (1, 9)


def test_plan_takes_a_loose_vanilla_txd():
    ide = {19836: ("BloodPool1", "particle", 50)}
    entries, problems = m.plan(ide, [19836], {"bloodpool1.dff": (0, 1)}, {}, {}, samp_cols={"bloodpool1": b"c"},
                               loose_txds={"particle": None})
    assert problems == [] and entries[19836]["txd"] == "particle"
    assert entries[19836]["src"]["txd"] == ("loose", "particle.txd")


def test_props_are_listed_with_their_dff_col_and_txd(tmp_path):
    (tmp_path / "props.lua").write_text('return {\n    [20201] = { dff = "ls_hatch", txd = "ls_hatch", dist = 150 },\n}\n',
                                        encoding="ascii")
    assert m.prop_files(tmp_path) == ["ls_hatch.col", "ls_hatch.dff", "ls_hatch.txd"]
    assert m.prop_files(tmp_path / "missing") == []
    meta = m.render_meta({}, props=m.prop_files(tmp_path))
    assert '    <file src="props.lua"/>' in meta and '    <file src="files/ls_hatch.txd"/>' in meta
    assert '<file src="props.lua"/>' not in m.render_meta({})


def test_the_ls_hatch_is_port_model_20201_with_its_own_txd():
    from tools import make_ls_hatch as h
    assert h.MODEL_ID == 20201 and h.TEXTURE == "pave_manhole1"
    assert '[20201] = { dff = "ls_hatch", txd = "ls_hatch", dist = 150 },' in h.render_props()


def test_fort_pieces_are_listed_with_their_dff_col_and_the_shared_txd(tmp_path):
    (tmp_path / "fort.lua").write_text('return {\n    [20301] = { dff = "fort_wall4", txd = "fort_kit", dist = 150 },\n'
                                       '    [20302] = { dff = "fort_wall2", txd = "fort_kit", dist = 150 },\n}\n', encoding="ascii")
    assert m.fort_files(tmp_path) == ["fort_wall2.col", "fort_wall2.dff", "fort_wall4.col", "fort_wall4.dff", "fort_kit.txd"]
    assert m.fort_files(tmp_path / "missing") == []
    meta = m.render_meta({}, fort=m.fort_files(tmp_path))
    assert '    <file src="fort.lua"/>' in meta and '    <file src="files/fort_kit.txd"/>' in meta
    assert '<file src="fort.lua"/>' not in m.render_meta({})


def test_the_fort_kit_ids_start_at_20301_and_render_without_blender():
    from tools import make_fort_kit as k
    ids = k.model_ids()
    assert min(ids.values()) == k.FORT_MODEL_MIN == 20301 and len(set(ids.values())) == len(ids)
    text = k.render_fort()
    assert text.count("txd = \"fort_kit\"") == len(ids) and "[20306] = { dff = \"fort_tower\"" in text
    for name, make in k.PIECES.items():
        parts, cols = make()
        assert parts and cols and {p[6] for p in parts} <= set(k.TEXTURES), name


def test_merge_txd_concatenates_the_textures_of_trimmed_dictionaries():
    from tools import make_fort_kit as k
    one = _rw(0x16, _rw(0x01, struct.pack("<HH", 1, 9)) + _native("sheet") + _rw(0x03, b""))
    two = _rw(0x16, _rw(0x01, struct.pack("<HH", 1, 9)) + _native("planks") + _rw(0x03, b""))
    out = k.merge_txd([one, two])
    assert b"sheet" in out and b"planks" in out and struct.unpack_from("<HH", out, 24) == (2, 9)
    assert struct.unpack_from("<III", out, 0)[1] == len(out) - 12
