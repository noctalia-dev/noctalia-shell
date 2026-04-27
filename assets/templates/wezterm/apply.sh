#!/usr/bin/env bash
set -euo pipefail

config_file="$HOME/.config/wezterm/wezterm.lua"
scheme_line='config.color_scheme = "Noctalia"'

if [ ! -f "$config_file" ]; then
    echo "Error: wezterm.lua not found at $config_file" >&2
    exit 1
fi

if ! grep -q "^\s*config\.color_scheme\s*=\s*['\"]Noctalia['\"]\s*" "$config_file"; then
    if grep -q '^\s*config\.color_scheme\s*=' "$config_file"; then
        sed -i "s|^\(\s*config\.color_scheme\s*=\s*\).*$|\1\"Noctalia\"|" "$config_file"
    elif grep -q '^\s*return\s*config' "$config_file"; then
        sed -i '/^\s*return\s*config/i\'"$scheme_line" "$config_file"
    else
        echo "Warning: config.color_scheme not set and return config not found in $config_file" >&2
    fi
fi

touch "$config_file"
