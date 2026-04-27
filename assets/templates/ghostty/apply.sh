#!/usr/bin/env bash
set -euo pipefail

config_files=("$HOME/.config/ghostty/config" "$HOME/.config/ghostty/config.ghostty")
found=false

for config_file in "${config_files[@]}"; do
    [ -f "$config_file" ] || continue
    found=true

    if grep -qE '^theme\s*=\s*noctalia$' "$config_file"; then
        :
    elif grep -qE '^theme\s*=' "$config_file"; then
        sed -i -E 's/^theme\s*=.*/theme = noctalia/' "$config_file"
    else
        echo "theme = noctalia" >>"$config_file"
    fi
done

if [ "$found" != true ]; then
    echo "Error: no ghostty config file found" >&2
    exit 1
fi

pgrep -f ghostty >/dev/null && pkill -SIGUSR2 ghostty || true
