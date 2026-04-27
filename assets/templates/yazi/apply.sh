#!/usr/bin/env bash
set -euo pipefail

config_file="$HOME/.config/yazi/theme.toml"

mkdir -p "$(dirname "$config_file")"

if [ ! -f "$config_file" ]; then
    cat >"$config_file" <<'EOF'
[flavor]
dark  = "noctalia"
light = "noctalia"
EOF
    exit 0
fi

if grep -q '^\[flavor\]' "$config_file"; then
    if sed -n '/^\[flavor\]/,/^\[/p' "$config_file" | grep -q '^dark\s*='; then
        sed -i '/^\[flavor\]/,/^\[/{s/^dark\s*=.*/dark  = "noctalia"/}' "$config_file"
    else
        sed -i '/^\[flavor\]/a dark  = "noctalia"' "$config_file"
    fi

    if sed -n '/^\[flavor\]/,/^\[/p' "$config_file" | grep -q '^light\s*='; then
        sed -i '/^\[flavor\]/,/^\[/{s/^light\s*=.*/light = "noctalia"/}' "$config_file"
    else
        sed -i '/^\[flavor\]/,/^dark/a light = "noctalia"' "$config_file"
    fi
else
    {
        echo ""
        echo "[flavor]"
        echo 'dark  = "noctalia"'
        echo 'light = "noctalia"'
    } >>"$config_file"
fi
