from pathlib import Path

from tools.convert import lang

FX = Path(__file__).parent / "fixtures"


def test_converts_colour_and_player_tokens():
    entries = lang.parse((FX / "English_excerpt").read_bytes(), encoding="ascii")
    assert entries["LANGCHANGE"] == " >  #FFFF00Language changed to English!"
    assert entries["WOUNDEDMSSG"] == "Wounded: %s\nSeverity: %s"
    assert entries["TELEPORTEDT"] == " >  %s#FFFF00 Has teleported to you"


def test_encoding_table_covers_all_upstream_files():
    assert lang.ENCODINGS["Russian"] == "cp1251" and lang.ENCODINGS["Cestina-Srpski"] == "iso8859_2"
    assert lang.ENCODINGS["Bosanski-Hrvatski-Srpski"] == "cp1250" and lang.ENCODINGS["Português"] == "cp1252"
    assert lang.CODES["English"] == "en"


def test_upstream_colours_and_key_hints():
    entries = lang.parse((FX / "English_excerpt").read_bytes(), encoding="ascii")
    # ScavengeSurvive.pwn: #define C_RED "{E85454}", C_BLUE "{33CCFF}"
    assert entries["BANNEDMESSG"] == " >  #E85454You are banned! #FFFF00Reason: #33CCFF%s"
    # {KEYTEXT_*} and ~k~~CONTROL~ become the port's default key labels instead of vanishing
    assert entries["M9Pistol_T"] == "Press [R] to reload, press [Y] to holster and hold [N] to remove ammo"
    assert entries["ITEMTWKBTNE"] == "Edit: [LALT]"
