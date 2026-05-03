#!/usr/bin/env bash
set -euo pipefail

config_file="$HOME/.config/cava/config"

if [ ! -f "$config_file" ]; then
    echo "Error: cava config file not found at $config_file" >&2
    exit 1
fi

if grep -q '^\[color\]' "$config_file"; then
    if sed -n '/^\[color\]/,/^\[/p' "$config_file" | grep -qE '^theme\s*=\s*"noctalia"'; then
        :
    elif sed -n '/^\[color\]/,/^\[/p' "$config_file" | grep -qE '^theme\s*='; then
        sed -i -E '/^\[color\]/,/^\[/{s/^theme\s*=.*/theme = "noctalia"/}' "$config_file"
    else
        sed -i '/^\[color\]/a theme = "noctalia"' "$config_file"
    fi
else
    printf '\n[color]\ntheme = "noctalia"\n' >>"$config_file"
fi

if pgrep -x cava >/dev/null; then
    if ! pgrep -ax cava | grep -q -- '-p.*stdin'; then
        pkill -USR1 -x cava || true
    fi
fi
