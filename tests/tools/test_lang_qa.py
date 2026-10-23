from tools import lang_qa


def test_unescape_and_placeholders():
    assert lang_qa.unescape(r"a\nb\"c\\d\65") == 'a\nb"c\\dA'
    assert lang_qa.placeholders("x %s y %02d z %.2f %%") == ["s", "d", "f"]


def test_every_language_loads():
    en = lang_qa.load("en")
    assert len(en) >= 500
    assert en["MUTEDUNMUTE"].startswith(" >  You are now un-muted")
    for code in lang_qa.CODES[1:]:
        assert len(lang_qa.load(code)) > 300, code


def test_no_leftovers_extras_or_unexpected_placeholder_mismatches():
    _, results = lang_qa.build()
    mismatched = set()
    for code, res in results.items():
        assert not res["leftovers"], code
        assert not res["extra"], code
        mismatched |= {(code, m[0]) for m in res["mismatched"]}
    assert mismatched == {("ru", "DEFTOOFASTE"), ("ru", "MACHPROCESS")}


def test_committed_report_is_current():
    text, _ = lang_qa.build()
    stale = "docs/languages-qa.md is stale: run python -m tools.lang_qa"
    assert lang_qa.REPORT.read_text(encoding="utf-8") == text, stale
