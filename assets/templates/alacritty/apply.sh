#!/usr/bin/env bash
set -euo pipefail

config_file="$HOME/.config/alacritty/alacritty.toml"
theme_path='~/.config/alacritty/themes/noctalia.toml'

mkdir -p "$(dirname "$config_file")"

if [ ! -f "$config_file" ]; then
    cat >"$config_file" <<'EOF'
[general]
import = [
    "~/.config/alacritty/themes/noctalia.toml"
]
EOF
    exit 0
fi

if grep -q 'noctalia\.toml' "$config_file"; then
    sed -i 's|"themes/noctalia.toml"|"~/.config/alacritty/themes/noctalia.toml"|g' "$config_file"
elif grep -q '^\[general\]' "$config_file"; then
    if grep -q '^import\s*=' "$config_file"; then
        sed -i '/^import\s*=\s*\[/,/\]/{/\]/s|]|    "'"$theme_path"'",\n]|}' "$config_file"
    else
        sed -i '/^\[general\]/a import = ["'"$theme_path"'"]' "$config_file"
    fi
else
    sed -i '1i [general]\nimport = ["'"$theme_path"'"]\n' "$config_file"
fi
