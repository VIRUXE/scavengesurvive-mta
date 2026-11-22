"""Builds the player wiki (wiki/*.md) into the static site served at https://wiki.scavengesurvive-reborn.com.

    python -m tools.wiki_site [--out DIR] [--strict] [--serve [PORT]]

Every page is written once in English as wiki/<Page>.md; wiki/<Page>.pt.md, when it exists, is its Portuguese. Each
language is staged under build/wiki/<lang>/ and built by MkDocs Material with the shared settings of
wiki-site/mkdocs.yml: English at the site root, Portuguese under /pt/, a page with no translation yet showing the
English one. Each language gets its own search index. Staging turns the wiki's own conventions into MkDocs ones:

- a link to a page by name (`[Fuel](Fuel)`, `[x](Area-69#getting-a-code)`) points to its .md file, Home is index.md;
- a picture `images/<path>` is docs/images/<path> (`images/items/<file>` is docs/images/items/all/<file>, the item
  renders), converted to WebP once into /images/ at the site root for both languages;
- the navigation is wiki/_Sidebar.md: a `**Section**` line opens a section, `- [Label](Page)` adds a page; the
  Portuguese labels are the titles of the translated pages and SECTIONS_PT below. The item pages stay out of the
  navigation (the Item Catalogue and the search reach them).

The pages workflow builds and deploys it on every push to wiki/; --serve also serves the result on
http://localhost:8000 to look at it locally (the language switch and the search need a server). Requires the pinned
packages of wiki-site/requirements.txt and Pillow.
"""
from __future__ import annotations

import argparse
import functools
import http.server
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
WIKI = ROOT / "wiki"
SITE_CFG = ROOT / "wiki-site"
IMAGES = ROOT / "docs" / "images"
FONTS = ROOT / "site" / "assets" / "fonts"
LOGO = ROOT / "site" / "assets" / "img" / "brand" / "logo-64.webp"
STAGE = ROOT / "build" / "wiki"
URL = "https://wiki.scavengesurvive-reborn.com/"
LANGS = ("en", "pt")
MAX_WIDTH = 1920
# the _Sidebar.md section titles in Portuguese
SECTIONS_PT = {
    "Home": "Início",
    "Start here": "Começar",
    "Character": "Personagem",
    "Items": "Itens",
    "Crafting & living": "Fabrico e sobrevivência",
    "Vehicles": "Veículos",
    "World": "Mundo",
}

PAGE_LINK = re.compile(r"(\]\(|href=\")([A-Za-z0-9][A-Za-z0-9\-]*)(#[^)\"\s]*)?(?=[)\"])")
IMAGE_REF = re.compile(r"(\]\(|src=\"|href=\")images/([^)\"\s]+?)\.(png|jpe?g|webp)(?=[)\"\s])")
SIDEBAR_SECTION = re.compile(r"^\*\*([^*\[]+)\*\*\s*$")
SIDEBAR_PAGE = re.compile(r"^\s*[-*]\s+\[([^\]]+)\]\(([^)#]+)\)")


def sources() -> dict[str, dict[str, Path]]:
    """lang -> stem -> the file that holds that page in that language (the English one where no translation exists)."""
    english = {p.stem: p for p in sorted(WIKI.glob("*.md")) if not p.name.startswith("_") and p.name.count(".") == 1}
    out = {"en": dict(english)}
    for lang in LANGS[1:]:
        out[lang] = {stem: (WIKI / f"{stem}.{lang}.md" if (WIKI / f"{stem}.{lang}.md").exists() else p) for stem, p in english.items()}
    orphans = [p.name for lang in LANGS[1:] for p in WIKI.glob(f"*.{lang}.md") if p.name.split(".")[0] not in english]
    if orphans:
        print("translations without an English page (not built):", ", ".join(sorted(orphans)))
    return out


def target(stem: str) -> str:
    return "index.md" if stem == "Home" else stem + ".md"


def image_source(path: str) -> Path:
    """The docs/images file behind a wiki picture path (without its extension's dot handling)."""
    return IMAGES / "items" / "all" / path[len("items/") :] if path.startswith("items/") else IMAGES / path


def stage_text(text: str, stems: set[str], pictures: set[str], here: str) -> str:
    """A page's text for MkDocs; `here` is its stem. Markdown links name the .md file (MkDocs turns them into URLs),
    links in raw HTML get the final relative URL, which MkDocs leaves alone."""

    def image(m: re.Match) -> str:
        path = m.group(2) + "." + m.group(3)
        pictures.add(path)
        return m.group(1) + "/images/" + m.group(2) + ".webp"

    def page(m: re.Match) -> str:
        stem = m.group(2)
        if stem not in stems:
            return m.group(0)
        if m.group(1) == "](":
            return m.group(1) + target(stem) + (m.group(3) or "")
        url = ("" if here == "Home" else "../") + ("" if stem == "Home" else stem + "/")
        return m.group(1) + (url or "./") + (m.group(3) or "")

    return PAGE_LINK.sub(page, IMAGE_REF.sub(image, text))


def title(path: Path) -> str | None:
    m = re.search(r"^# (.+)$", path.read_text(encoding="utf8"), re.M)
    return m.group(1).strip() if m else None


def nav(lang: str, files: dict[str, Path]) -> list:
    """The navigation of a language from _Sidebar.md: a list of {label: file} and {section: [{label: file}]}."""
    out: list = [{SECTIONS_PT["Home"] if lang == "pt" else "Home": "index.md"}]
    section = None
    for line in (WIKI / "_Sidebar.md").read_text(encoding="utf8").splitlines():
        m = SIDEBAR_SECTION.match(line)
        if m:
            name = m.group(1).strip()
            section = []
            out.append({SECTIONS_PT.get(name, name) if lang == "pt" else name: section})
            continue
        m = SIDEBAR_PAGE.match(line)
        if m and section is not None:
            label, stem = m.group(1), m.group(2).strip()
            if stem not in files or stem == "Home":
                continue
            if lang != "en" and files[stem].name.endswith(f".{lang}.md"):
                label = title(files[stem]) or label
            section.append({label: target(stem)})
    return out


def yaml_nav(entries: list, indent: int = 2) -> str:
    out = []
    pad = " " * indent
    for e in entries:
        ((label, value),) = e.items()
        key = '"' + label.replace("\\", "\\\\").replace('"', '\\"') + '"'
        if isinstance(value, list):
            out.append(f"{pad}- {key}:")
            out.append(yaml_nav(value, indent + 4))
        else:
            out.append(f"{pad}- {key}: {value}")
    return "\n".join(out)


def stage(lang: str, files: dict[str, Path], out: Path, pictures: set[str]) -> Path:
    """Writes build/wiki/<lang>/docs and its mkdocs.yml; returns the config path."""
    base = STAGE / lang
    docs = base / "docs"
    if base.exists():
        shutil.rmtree(base)
    docs.mkdir(parents=True)
    stems = set(files)
    for stem, path in files.items():
        text = stage_text(path.read_text(encoding="utf8"), stems, pictures, stem)
        (docs / target(stem)).write_text(text, encoding="utf8", newline="\n")
    assets = docs / "assets"
    shutil.copytree(SITE_CFG / "assets", assets)
    shutil.copytree(FONTS, assets / "fonts")
    shutil.copy2(LOGO, assets / LOGO.name)
    site_dir = out if lang == "en" else out / lang
    lines = [
        "INHERIT: " + (SITE_CFG / "mkdocs.yml").as_posix(),
        "docs_dir: docs",
        "site_dir: " + site_dir.resolve().as_posix(),
        "site_url: " + URL + ("" if lang == "en" else lang + "/"),
        "theme:",
        "  language: " + lang,
        "plugins:",
        "  - search:",
        "      lang: " + lang,
        "nav:",
        yaml_nav(nav(lang, files)),
        "",
    ]
    cfg = base / "mkdocs.yml"
    cfg.write_text("\n".join(lines), encoding="utf8", newline="\n")
    return cfg


def convert_picture(src: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(src) as im:
        im = im.convert("RGBA" if im.mode in ("RGBA", "LA", "P") else "RGB")
        if im.width > MAX_WIDTH:
            im = im.resize((MAX_WIDTH, round(im.height * MAX_WIDTH / im.width)), Image.Resampling.LANCZOS)
        im.save(dest, "WEBP", quality=85, method=4)


def convert_pictures(pictures: set[str], out: Path) -> None:
    """Every picture the pages show, as WebP under <out>/images (at most MAX_WIDTH wide, transparency kept)."""
    missing = sorted(p for p in pictures if not image_source(p).exists())
    if missing:
        sys.exit("pictures not found in docs/images: " + ", ".join(missing))
    jobs = [(image_source(p), out / "images" / (p.rsplit(".", 1)[0] + ".webp")) for p in sorted(pictures)]
    with ThreadPoolExecutor() as pool:
        list(pool.map(lambda job: convert_picture(*job), jobs))
    print(f"{len(jobs)} pictures converted")


def build(out: Path, strict: bool) -> None:
    if out.exists():
        shutil.rmtree(out)
    per_lang = sources()
    pictures: set[str] = set()
    env = {**os.environ, "NO_MKDOCS_2_WARNING": "1"}
    for lang in LANGS:
        cfg = stage(lang, per_lang[lang], out, pictures)
        own = sum(1 for p in per_lang[lang].values() if lang == "en" or p.name.endswith(f".{lang}.md"))
        print(f"[{lang}] {len(per_lang[lang])} pages, {own} written in this language")
        cmd = [sys.executable, "-m", "mkdocs", "build", "-q", "-f", str(cfg)] + (["--strict"] if strict else [])
        subprocess.run(cmd, check=True, cwd=cfg.parent, env=env)
    convert_pictures(pictures, out)
    print("built", out)


def serve(out: Path, port: int) -> None:
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(out))
    print(f"serving {out} on http://localhost:{port}/ (Ctrl+C stops)", flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "build" / "wiki-site"), help="where the site is written (default build/wiki-site)")
    ap.add_argument("--strict", action="store_true", help="fail on MkDocs warnings (broken links and anchors)")
    ap.add_argument("--serve", nargs="?", const=8000, type=int, metavar="PORT", help="serve the built site afterwards")
    a = ap.parse_args()
    out = Path(a.out)
    build(out, a.strict)
    if a.serve:
        serve(out, a.serve)


if __name__ == "__main__":
    main()
