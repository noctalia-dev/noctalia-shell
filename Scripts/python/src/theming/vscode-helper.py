#!/usr/bin/env python3
# Finds the newest installed Noctalia theme extension for VSCode/VSCodium.

import sys
from pathlib import Path


def parse_version(name: str, prefix: str) -> tuple:
    # Strip prefix and -universal suffix, then split "0.0.6" into (0, 0, 6) for comparison
    return tuple(int(x) for x in name[len(prefix):].removesuffix("-universal").split("."))


def find_newest_theme(extensions_dir: Path, prefix: str) -> str | None:
    # Bail early if the extensions directory doesn't exist
    if not extensions_dir.is_dir():
        return None
    # Collect all directories matching the extension prefix
    candidates = [d for d in extensions_dir.iterdir() if d.is_dir() and d.name.startswith(prefix)]
    if candidates:
        # Pick the highest version and return the full theme file path
        return str(max(candidates, key=lambda d: parse_version(d.name, prefix)) / "themes" / "NoctaliaTheme-color-theme.json")
    return None


if __name__ == "__main__":
    # Resolve ~ in the provided extensions directory path
    extensions_dir = Path(sys.argv[1]).expanduser()
    prefix = sys.argv[2] if len(sys.argv) > 2 else "noctalia.noctaliatheme-"

    # Print the resolved path to stdout for the QML Process to capture
    result = find_newest_theme(extensions_dir, prefix)
    if result:
        print(result)
    else:
        print(f"No matching extension found in {extensions_dir}", file=sys.stderr)
        sys.exit(1)
