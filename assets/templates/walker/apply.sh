#!/usr/bin/env bash
set -euo pipefail

config_file="$HOME/.config/walker/config.toml"

if [ ! -f "$config_file" ]; then
    echo "Error: walker config file not found at $config_file" >&2
    exit 1
fi

if grep -qE '^theme\s*=\s*"noctalia"' "$config_file"; then
    :
elif grep -qE '^theme\s*=' "$config_file"; then
    sed -i -E 's/^theme\s*=.*/theme = "noctalia"/' "$config_file"
else
    echo 'theme = "noctalia"' >>"$config_file"
fi
