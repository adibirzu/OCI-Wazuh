#!/usr/bin/env python3
import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]
SCAN_DIRS = [ROOT / "docs/wiki", ROOT / "lessons", ROOT / "reference"]
MARKDOWN_LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")


class LinkParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key in {"href", "src"} and value:
                self.links.append(value)


def is_external(target):
    parsed = urlsplit(target)
    return parsed.scheme in {"http", "https", "mailto"} or target.startswith("#")


def normalize_target(raw):
    target = raw.strip()
    if not target or is_external(target):
        return None
    if " " in target and not target.startswith("<"):
        target = target.split(" ", 1)[0]
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1]
    target = target.split("#", 1)[0]
    target = target.split("?", 1)[0]
    return unquote(target)


def links_for(path):
    text = path.read_text(encoding="utf-8")
    if path.suffix.lower() in {".html", ".htm"}:
        parser = LinkParser()
        parser.feed(text)
        return parser.links
    if path.suffix.lower() == ".md":
        return [match.group(1) for match in MARKDOWN_LINK.finditer(text)]
    return []


def main():
    failures = []
    files = []
    for directory in SCAN_DIRS:
        files.extend(sorted(directory.rglob("*.md")))
        files.extend(sorted(directory.rglob("*.html")))

    for source in files:
        for raw_link in links_for(source):
            target = normalize_target(raw_link)
            if target is None:
                continue
            resolved = (source.parent / target).resolve()
            try:
                resolved.relative_to(ROOT)
            except ValueError:
                failures.append((source, raw_link, "outside repository"))
                continue
            if not resolved.exists():
                failures.append((source, raw_link, "missing target"))

    if failures:
        for source, link, reason in failures:
            print(f"{source.relative_to(ROOT)}: broken_link={link} reason={reason}", file=sys.stderr)
        return 1

    print(f"teaching_links=ready")
    print(f"checked_files={len(files)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
