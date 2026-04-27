#!/usr/bin/env bash
set -euo pipefail

icon_source="${1:-}"
icon_target="$HOME/.local/share/vicinae/themes/noctalia.svg"

if [ -n "$icon_source" ] && [ -f "$icon_source" ]; then
    mkdir -p "$(dirname "$icon_target")"
    cp --update=none "$icon_source" "$icon_target"
fi

vicinae theme set noctalia
