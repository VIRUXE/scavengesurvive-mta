from pathlib import Path

from tools import extract_ped_models as peds
from tools import extract_samp_models as objects


def test_peds_manifest_round_trips(tmp_path: Path) -> None:
    text = peds.render_peds({287: "army_nohat", 283: "csher_nohat"})
    assert text.splitlines()[2:4] == ['    [283] = { dff = "csher_nohat" },', '    [287] = { dff = "army_nohat" },']
    (tmp_path / "peds.lua").write_text(text, encoding="ascii")
    assert peds.read_peds(tmp_path / "peds.lua") == {283: "csher_nohat", 287: "army_nohat"}
    assert peds.read_peds(tmp_path / "missing.lua") == {}


def test_meta_lists_both_manifests(tmp_path: Path) -> None:
    (tmp_path / "manifest.lua").write_text(
        'return {\n    [11712] = { dff = "cross1", txd = "cross1", dist = 50 },\n'
        '    [11692] = { dff = "a51landbit1", txdModel = 16093, dist = 599 },\n}\n',
        encoding="ascii",
    )
    (tmp_path / "peds.lua").write_text(peds.render_peds({283: "csher_nohat"}), encoding="ascii")
    objects.write_meta(tmp_path)
    meta = (tmp_path / "meta.xml").read_text(encoding="ascii")
    for line in (
        '<file src="files/cross1.dff"/>',
        '<file src="files/cross1.txd"/>',
        '<file src="files/a51landbit1.col"/>',
        '<file src="peds.lua"/>',
        '<file src="files/csher_nohat.dff"/>',
        '<export function="hatlessSkin" type="client"/>',
    ):
        assert line in meta
    assert meta.index('<file src="peds.lua"/>') > meta.index('<file src="files/cross1.txd"/>')


def test_meta_without_peds_has_no_ped_lines(tmp_path: Path) -> None:
    (tmp_path / "manifest.lua").write_text('return {\n    [11712] = { dff = "cross1", txd = "cross1", dist = 50 },\n}\n')
    objects.write_meta(tmp_path)
    meta = (tmp_path / "meta.xml").read_text(encoding="ascii")
    assert "peds.lua" not in meta
    assert "_nohat" not in meta


def test_every_headgear_skin_names_its_model() -> None:
    for skin, (dff, texture, blocks, above) in peds.HEADGEAR.items():
        assert 0 <= skin <= 312
        assert dff and texture
        assert blocks in ("auto", "*") or all(len(b.split(",")) == 2 for b in blocks.split(";"))
        assert 0 < above < 0.2
