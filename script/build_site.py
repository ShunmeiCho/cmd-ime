#!/usr/bin/env python3
"""Build the website into one static page per language.

site/index.html holds all three languages side by side (class i-en / i-zh / i-ja). Search engines
index what the raw HTML says, so each language gets its own URL whose HTML carries only that
language: its own title, description, canonical and hreflang set, and a fixed data-ui for the
scripts. The software version in the structured data comes from VERSION, so a release keeps it
current.

    python3 script/build_site.py [out_dir]     # default: _site
"""
import html
import re
import shutil
import sys
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
BASE_URL = "https://shunmeicho.github.io/cmd-ime/"

LANGS = {
    "en": {
        "dir": "",
        "class": "i-en",
        "title": "CmdIME 0.12.0 by ShunmeiCho - input sources per app on macOS",
        "description": "One key per input source, App Rules, App Memory, Adaptive themes and portable settings. "
        "CmdIME 0.12.0 for Apple silicon, macOS 13+. Preview: signed, not notarized.",
        "og_title": "CmdIME 0.12.0 - one key per input source, a slot for each app",
        "og_description": "Drag apps onto slots, restore your input source after password fields, and see a "
        "bubble for every switch. Adaptive themes and portable settings. Apple silicon only.",
    },
    "zh-CN": {
        "dir": "zh-cn/",
        "class": "i-zh",
        "title": "CmdIME 0.12.0 by ShunmeiCho - macOS 按应用设定输入源",
        "description": "每个输入源一个专属键，支持应用规则、App Memory、Adaptive 主题和设置迁移。"
        "CmdIME 0.12.0 仅支持 Apple 芯片，需 macOS 13 或更高版本。预览版：已签名，未公证。",
        "og_title": "CmdIME 0.12.0 - 每个输入源一个专属键，按应用设定槽位",
        "og_description": "把应用拖到槽位上，离开密码框后切回输入源，任何切换都有气泡提示。"
        "支持 Adaptive 主题和设置迁移，仅支持 Apple 芯片。",
    },
    "ja": {
        "dir": "ja/",
        "class": "i-ja",
        "title": "CmdIME 0.12.0 by ShunmeiCho - macOS のアプリごとの入力ソース",
        "description": "入力ソースごとの専用キー、App Rules、App Memory、Adaptive テーマ、持ち運べる設定。"
        "CmdIME 0.12.0 は Apple シリコン専用、macOS 13 以降。プレビュー版：署名済み、公証なし。",
        "og_title": "CmdIME 0.12.0 - 入力ソースごとに専用キー、アプリごとにスロット",
        "og_description": "アプリをスロットにドラッグ。パスワード欄のあと元の入力ソースへ戻り、切り替えにはバブルを表示。"
        "Adaptive テーマと持ち運べる設定。Apple シリコン専用。",
    },
}
LANG_CLASSES = {spec["class"] for spec in LANGS.values()}
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}
URL_ATTRS = {"src", "href", "poster"}
ABSOLUTE = re.compile(r"^([a-z][a-z0-9+.-]*:|/|#)", re.I)


def page_url(lang: str) -> str:
    return BASE_URL + LANGS[lang]["dir"]


class LanguageFilter(HTMLParser):
    """Re-emits the page, dropping elements marked for another language and fixing relative URLs."""

    def __init__(self, keep_class: str, prefix: str) -> None:
        super().__init__(convert_charrefs=False)
        self.drop = LANG_CLASSES - {keep_class}
        self.prefix = prefix
        self.out = []
        self.skip_depth = 0

    def _classes(self, attrs: list[tuple[str, str | None]]) -> set[str]:
        return set((dict(attrs).get("class") or "").split())

    def _tag(self, tag: str, attrs: list[tuple[str, str | None]], close: str = "") -> str:
        parts = [tag]
        for name, value in attrs:
            if value is None:
                parts.append(name)
                continue
            if name in URL_ATTRS and self.prefix and not ABSOLUTE.match(value):
                value = self.prefix + value
            parts.append(f'{name}="{html.escape(value, quote=True)}"')
        return "<" + " ".join(parts) + close + ">"

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if self.skip_depth:
            if tag not in VOID:
                self.skip_depth += 1
            return
        if self._classes(attrs) & self.drop:
            if tag not in VOID:
                self.skip_depth = 1
            return
        self.out.append(self._tag(tag, attrs))

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if self.skip_depth or self._classes(attrs) & self.drop:
            return
        self.out.append(self._tag(tag, attrs, " /"))

    def handle_endtag(self, tag: str) -> None:
        if self.skip_depth:
            if tag not in VOID:
                self.skip_depth -= 1
            return
        self.out.append(f"</{tag}>")

    def _raw(self, text: str) -> None:
        if not self.skip_depth:
            self.out.append(text)

    def handle_data(self, data: str) -> None:
        self._raw(data)

    def handle_entityref(self, name: str) -> None:
        self._raw(f"&{name};")

    def handle_charref(self, name: str) -> None:
        self._raw(f"&#{name};")

    def handle_comment(self, data: str) -> None:
        self._raw(f"<!--{data}-->")

    def handle_decl(self, decl: str) -> None:
        self._raw(f"<!{decl}>")


def replace_once(text: str, pattern: str, replacement: str) -> str:
    new, count = re.subn(pattern, lambda _: replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"build_site: expected exactly one match for {pattern!r}")
    return new


def head_links(lang: str) -> str:
    links = [f'<link rel="canonical" href="{page_url(lang)}">']
    for other in LANGS:
        links.append(f'<link rel="alternate" hreflang="{other}" href="{page_url(other)}">')
    links.append(f'<link rel="alternate" hreflang="x-default" href="{page_url("en")}">')
    return "\n".join(links)


def build_page(source: str, lang: str, version: str) -> str:
    spec = LANGS[lang]
    prefix = "../" if spec["dir"] else ""
    esc = lambda s: html.escape(s, quote=True)
    page = source
    page = replace_once(page, r'<html lang="en" data-ui="en">', f'<html lang="{lang}" data-ui="{lang}">')
    page = replace_once(page, r"<title>.*?</title>", f"<title>{esc(spec['title'])}</title>")
    page = replace_once(page, r'<meta name="description" content="[^"]*">',
                        f'<meta name="description" content="{esc(spec["description"])}">')
    page = replace_once(page, r'<link rel="canonical"[^>]*>\s*(<link rel="alternate" hreflang[^>]*>\s*)+',
                        head_links(lang) + "\n")
    for prop, key in (("og:title", "og_title"), ("og:description", "og_description")):
        page = replace_once(page, rf'<meta property="{prop}" content="[^"]*">',
                            f'<meta property="{prop}" content="{esc(spec[key])}">')
    for name, key in (("twitter:title", "og_title"), ("twitter:description", "og_description")):
        page = replace_once(page, rf'<meta name="{name}" content="[^"]*">',
                            f'<meta name="{name}" content="{esc(spec[key])}">')
    page = replace_once(page, r'<meta property="og:url" content="[^"]*">',
                        f'<meta property="og:url" content="{page_url(lang)}">')
    page = replace_once(page, r'"softwareVersion": "[^"]*"', f'"softwareVersion": "{version}"')
    # The language is fixed by the URL now; the pre-paint picker only runs on the English page,
    # where it forwards a reader who chose, or whose browser prefers, another language.
    picker = r"<script>\s*/\* Pick the language before first paint.*?</script>\s*"
    page = replace_once(page, picker, ROOT_REDIRECT if not spec["dir"] else "")

    parser = LanguageFilter(spec["class"], prefix)
    parser.feed(page)
    parser.close()
    out = "".join(parser.out)
    # Mark this page's own link in the language switcher.
    out = out.replace(f'data-set-lang="{lang}"', f'data-set-lang="{lang}" aria-current="page"', 1)
    return out


ROOT_REDIRECT = """<script>
/* Forward to the reader's language: an old ?lang= link, a saved choice, or the browser's first
   language. English readers and crawlers stay here. */
(function () {
  var paths = { "zh-CN": "zh-cn/", "ja": "ja/" };
  function norm(t) { t = String(t || "").toLowerCase(); return t.indexOf("zh") === 0 ? "zh-CN" : t.indexOf("ja") === 0 ? "ja" : t.indexOf("en") === 0 ? "en" : null; }
  var q = /[?&]lang=([^&#]+)/.exec(location.search), saved = null;
  try { saved = norm(localStorage.getItem("cmdime-lang")); } catch (e) {}
  var lang = (q && norm(decodeURIComponent(q[1]))) || saved || norm((navigator.languages || [])[0] || navigator.language);
  if (paths[lang]) location.replace(paths[lang] + location.hash);
})();
</script>
"""


def sitemap() -> str:
    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">']
    for lang in LANGS:
        lines.append("  <url>")
        lines.append(f"    <loc>{page_url(lang)}</loc>")
        for other in LANGS:
            lines.append(f'    <xhtml:link rel="alternate" hreflang="{other}" href="{page_url(other)}"/>')
        lines.append(f'    <xhtml:link rel="alternate" hreflang="x-default" href="{page_url("en")}"/>')
        lines.append("  </url>")
    lines.append("</urlset>")
    return "\n".join(lines) + "\n"


def main() -> None:
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "_site"
    version = (ROOT / "VERSION").read_text().strip()
    if not re.fullmatch(r"[0-9]+(\.[0-9]+)*", version):
        raise SystemExit(f"build_site: VERSION is not a version: {version!r}")
    if out_dir.exists():
        shutil.rmtree(out_dir)
    shutil.copytree(SITE, out_dir, ignore=shutil.ignore_patterns("index.html", "sitemap.xml", ".DS_Store"))
    source = (SITE / "index.html").read_text()
    for lang, spec in LANGS.items():
        target = out_dir / spec["dir"] / "index.html"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(build_page(source, lang, version))
    (out_dir / "sitemap.xml").write_text(sitemap())
    print(f"built {', '.join(LANGS)} into {out_dir} (version {version})")


if __name__ == "__main__":
    main()
