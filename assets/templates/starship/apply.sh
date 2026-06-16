#!/usr/bin/env bash
set -euo pipefail

palette_file="${XDG_CACHE_HOME:-$HOME/.cache}/noctalia/starship-palette.toml"
config_file="${STARSHIP_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml}"
marker_begin="# >>> NOCTALIA STARSHIP PALETTE >>>"
marker_end="# <<< NOCTALIA STARSHIP PALETTE <<<"

if [ ! -f "$palette_file" ]; then
    echo "Error: Starship palette file not found at $palette_file" >&2
    exit 1
fi

mkdir -p "$(dirname "$config_file")"

if [ ! -f "$config_file" ]; then
    echo 'palette = "noctalia"' >"$config_file"
else
    if grep -qE '^palette\s*=' "$config_file"; then
        sed -i -E 's/^palette\s*=.*/palette = "noctalia"/' "$config_file"
    elif grep -qE '^"\$schema"' "$config_file"; then
        sed -i '/^"\$schema"/a palette = "noctalia"' "$config_file"
    else
        sed -i '1i palette = "noctalia"' "$config_file"
    fi

    if grep -qF "$marker_begin" "$config_file"; then
        begin_regex=$(printf '%s' "$marker_begin" | sed 's/[[\.*^$()+?{|]/\\&/g')
        end_regex=$(printf '%s' "$marker_end" | sed 's/[[\.*^$()+?{|]/\\&/g')
        sed -i "/$begin_regex/,/$end_regex/d" "$config_file"
    fi

    # Drop trailing blank lines so the leading newline below does not accumulate
    sed -i -e :a -e '/^\n*$/{$d;N;ba}' "$config_file"
fi

{
    echo ""
    echo "$marker_begin"
    cat "$palette_file"
    echo "$marker_end"
} >>"$config_file"
