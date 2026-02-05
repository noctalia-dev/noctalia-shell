#!/usr/bin/env python3
# Finds all installed Noctalia theme extensions for VSCode/VSCodium.

import sys
from pathlib import Path


def find_all_noctalia_themes(extensions_dir: Path, prefix: str) -> list[str]:
    # Bail early if the extensions directory doesn't exist
    if not extensions_dir.is_dir():
        return []
    # Collect all directories matching the extension prefix
    candidates = [d for d in extensions_dir.iterdir() if d.is_dir() and d.name.startswith(prefix)]
    # Return theme file paths for all matching extensions
    return [str(d / "themes" / "NoctaliaTheme-color-theme.json") for d in candidates]


if __name__ == "__main__":
    # Resolve ~ in the provided extensions directory path
    extensions_dir = Path(sys.argv[1]).expanduser()
    prefix = sys.argv[2] if len(sys.argv) > 2 else "noctalia.noctaliatheme-"

    # Print the resolved paths to stdout for the QML Process to capture
    results = find_all_noctalia_themes(extensions_dir, prefix)
    if results:
        for path in results:
            print(path)
    else:
        print(f"No matching extension found in {extensions_dir}", file=sys.stderr)
        sys.exit(1)