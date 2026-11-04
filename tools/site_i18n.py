"""Collects the website's translatable texts and checks the translations.

    python -m tools.site_i18n            # report what each site/lang/<code>.json lacks or no longer needs
    python -m tools.site_i18n --dump     # print every key with its English text as JSON (the skeleton of a new language)

Texts are the innerHTML of every `data-i18n="key"` element and the attribute values of every `data-i18n-attr="attr:key"`
in site/*.html, plus the fallback strings the script passes to t("key", "English") in site/assets/js/site.js. The same
key must carry the same English everywhere (the tool reports a conflict otherwise). Translations live in
site/lang/<code>.json as `{"key": "text"}`; data files (site/data/*.json) carry their own `{"en": …, "pt": …}` objects
and are checked for a `pt` next to every `en`.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "site"
TAG = re.compile(r"<(\w+)([^>]*?)\sdata-i18n=\"([^\"]+)\"([^>]*)>", re.S)
ATTR = re.compile(r"data-i18n-attr=\"([^\"]+)\"")
T_CALL = re.compile(r"\bt\(\"([^\"]+)\",\s*\"((?:[^\"\\]|\\.)*)\"\)")
VOID = {"input", "img", "br", "hr", "meta", "link"}


def inner_html(html: str, start: int, tag: str) -> str:
    """The innerHTML of the element whose start tag ends at `start` (nested same-name tags are balanced)."""
    depth, pos = 1, start
    open_re = re.compile(rf"<{tag}\b[^>]*>|</{tag}>")
    while depth:
        m = open_re.search(html, pos)
        if not m:
            raise ValueError(f"unclosed <{tag}> at {start}")
        depth += -1 if m.group().startswith("</") else 1
        pos = m.end()
        if depth == 0:
            return html[start : m.start()].strip()
    return ""


def collect() -> dict[str, str]:
    texts: dict[str, str] = {}
    conflicts: list[str] = []

    def put(key: str, text: str, where: str) -> None:
        text = re.sub(r"\s+", " ", text).strip()
        if key in texts and texts[key] != text:
            conflicts.append(f"{key}: {where!r} differs from an earlier use")
        texts.setdefault(key, text)

    for page in sorted(SITE.glob("*.html")):
        html = page.read_text(encoding="utf-8")
        for m in TAG.finditer(html):
            tag, key = m.group(1), m.group(3)
            if tag in VOID:
                continue
            put(key, inner_html(html, m.end(), tag), page.name)
        for m in re.finditer(r"<(\w+)([^>]*?)>", html):
            attrs = m.group(2)
            a = ATTR.search(attrs)
            if not a:
                continue
            for pair in a.group(1).split(","):
                attr, key = pair.split(":")
                v = re.search(rf"\s{re.escape(attr)}=\"([^\"]*)\"", attrs)
                put(key, v.group(1) if v else "", page.name)
    js = (SITE / "assets" / "js" / "site.js").read_text(encoding="utf-8")
    for m in T_CALL.finditer(js):
        put(m.group(1), m.group(2).replace('\\"', '"'), "site.js")
    if conflicts:
        print("CONFLICTS:\n  " + "\n  ".join(conflicts), file=sys.stderr)
    return texts


def check_data(code: str) -> list[str]:
    missing: list[str] = []

    def walk(node, path: str) -> None:
        if isinstance(node, dict):
            if "en" in node and code not in node:
                missing.append(path)
            for k, v in node.items():
                walk(v, f"{path}.{k}")
        elif isinstance(node, list):
            for i, v in enumerate(node):
                walk(v, f"{path}[{i}]")

    for f in sorted((SITE / "data").glob("*.json")):
        walk(json.loads(f.read_text(encoding="utf-8")), f.name)
    return missing


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dump", action="store_true")
    args = parser.parse_args()
    texts = collect()
    if args.dump:
        print(json.dumps(texts, indent=1, ensure_ascii=False))
        return
    print(f"{len(texts)} texts in site/*.html and site.js")
    for lang in sorted((SITE / "lang").glob("*.json")):
        code = lang.stem
        tr = json.loads(lang.read_text(encoding="utf-8"))
        missing = [k for k in texts if k not in tr]
        stale = [k for k in tr if k not in texts]
        same = [k for k in texts if k in tr and tr[k] == texts[k] and len(texts[k]) > 3 and not texts[k].isupper()]
        print(f"{code}: {len(tr)} translated, {len(missing)} missing, {len(stale)} stale, {len(same)} identical to English")
        for k in missing:
            print(f"  missing  {k}")
        for k in stale:
            print(f"  stale    {k}")
        for k in same:
            print(f"  same     {k}: {texts[k][:60]}")
        data_missing = check_data(code)
        if data_missing:
            print(f"  data without {code}: {len(data_missing)}")
            for p in data_missing[:40]:
                print(f"    {p}")


if __name__ == "__main__":
    main()
