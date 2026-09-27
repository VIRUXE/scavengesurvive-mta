from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_repo_metadata_files_exist():
    for name in ["LICENSE", "LICENSE-MPL-2.0", "LICENSE-CC-BY-SA-4.0", "THIRD_PARTY_NOTICES.md",
                 "CLAUDE.md", ".luacheckrc", "stylua.toml", ".luacheck/mta_shared.lua"]:
        assert (ROOT / name).exists(), name


def test_gitattributes_forces_lf_for_lua():
    assert "*.lua text eol=lf" in (ROOT / ".gitattributes").read_text()
