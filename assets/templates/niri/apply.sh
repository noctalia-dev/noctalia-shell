#!/usr/bin/env bash
set -euo pipefail

config_file="${XDG_CONFIG_HOME:-$HOME/.config}/niri/config.kdl"
include_line='include "~/.config/niri/noctalia.kdl"'

mkdir -p "$(dirname "$config_file")"

if [ ! -f "$config_file" ]; then
    printf '%s\n' "$include_line" >"$config_file"
    exit 0
fi

if ! grep -q 'include ".*noctalia\.kdl"' "$config_file"; then
    printf '\n%s\n' "$include_line" >>"$config_file"
fi
