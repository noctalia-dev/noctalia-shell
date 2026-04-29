#!/usr/bin/env bash
set -euo pipefail

config_file="${XDG_CONFIG_HOME:-$HOME/.config}/mango/mango.conf"
include_line='include "~/.config/mango/noctalia.conf"'

mkdir -p "$(dirname "$config_file")"

if [ ! -f "$config_file" ]; then
    printf '%s\n' "$include_line" >"$config_file"
    exit 0
fi

if ! grep -q 'include ".*noctalia\.conf"' "$config_file"; then
    printf '\n%s\n' "$include_line" >>"$config_file"
fi
