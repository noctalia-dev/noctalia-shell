#!/usr/bin/env bash
set -euo pipefail

config_file="$HOME/.config/mango/config.conf"
include_line="source=$HOME/.config/mango/noctalia.conf"

mkdir -p "$(dirname "$config_file")"

if [ ! -f "$config_file" ]; then
    printf '%s\n' "$include_line" >"$config_file"
    exit 0
fi

if ! grep -q 'source=.*noctalia\.conf' "$config_file"; then
    printf '\n%s\n' "$include_line" >>"$config_file"
fi
