#!/usr/bin/env python3

import argparse
import json
import re
from pathlib import Path


HEADER_RE = re.compile(r"<!--(.*?)-->", re.DOTALL)
FIELD_RE = re.compile(r"^\s*([A-Za-z_]+):\s*(.*?)\s*$")
CONTROL_RE = re.compile(r"[\x00-\x1F\x7F]")
UNCATEGORIZED = "Uncategorized"


def parse_args():
    parser = argparse.ArgumentParser(description="Generate Noctalia Tabler glyph metadata.")
    parser.add_argument("--tabler-root", required=True, help="Path to the local tabler-icons checkout")
    parser.add_argument("--output", required=True, help="Path to write tabler.json")
    return parser.parse_args()


def parse_front_matter(path: Path):
    text = path.read_text(encoding="utf-8")
    match = HEADER_RE.search(text)
    if match is None:
        raise ValueError(f"{path}: missing SVG header comment")

    fields = {}
    for raw_line in match.group(1).splitlines():
        line = raw_line.rstrip("\n")
        field_match = FIELD_RE.match(line)
        if field_match is None:
            continue
        value = field_match.group(2).strip()
        if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
            value = value[1:-1]
        fields[field_match.group(1)] = value
    return fields


def validate_category(path: Path, category: str):
    if CONTROL_RE.search(category):
        raise ValueError(f"{path}: category contains control characters")
    if category != category.strip():
        raise ValueError(f"{path}: category has leading or trailing whitespace")


def validate_unicode(path: Path, value: str):
    if not value:
        raise ValueError(f"{path}: missing unicode")
    if CONTROL_RE.search(value):
        raise ValueError(f"{path}: unicode contains control characters")
    if not re.fullmatch(r"[0-9A-Fa-f]{4,6}", value):
        raise ValueError(f"{path}: invalid unicode '{value}'")


def build_metadata(tabler_root: Path):
    icons_root = tabler_root / "icons"
    entries = {}

    for style in ("outline", "filled"):
        for svg_path in sorted((icons_root / style).glob("*.svg")):
            fields = parse_front_matter(svg_path)
            category = fields.get("category", "").strip() or UNCATEGORIZED
            unicode_value = fields.get("unicode", "")
            validate_category(svg_path, category)
            validate_unicode(svg_path, unicode_value)

            name = svg_path.stem if style == "outline" else f"{svg_path.stem}-filled"
            entry = {
                "codepoint": f"U+{unicode_value.upper()}",
                "category": category,
            }
            previous = entries.get(name)
            if previous is not None and previous != entry:
                raise ValueError(f"{svg_path}: duplicate icon '{name}' with mismatched metadata")
            entries[name] = entry

    return dict(sorted(entries.items()))


def main():
    args = parse_args()
    metadata = build_metadata(Path(args.tabler_root))
    output_path = Path(args.output)
    output_path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
