#!/usr/bin/env bash
set -euo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/labwc"
theme_dir="${XDG_DATA_HOME:-$HOME/.local/share}/themes/noctalia/openbox-3"
theme_file="$theme_dir/themerc"
source_theme="$config_dir/noctalia.conf"
rc_file="$config_dir/rc.xml"

mkdir -p "$config_dir" "$theme_dir"

if [ -f "$source_theme" ]; then
    cp -f "$source_theme" "$theme_file"
fi

if [ ! -f "$rc_file" ]; then
    cat >"$rc_file" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<labwc_config>
  <theme>
    <name>noctalia</name>
  </theme>
</labwc_config>
EOF
    exit 0
fi

if grep -q '<theme>' "$rc_file" && grep -q '<name>.*</name>' "$rc_file"; then
    sed -i 's|<name>.*</name>|<name>noctalia</name>|' "$rc_file"
elif grep -q '<theme>' "$rc_file"; then
    sed -i 's|<theme>|<theme>\n    <name>noctalia</name>|' "$rc_file"
else
    sed -i '1i <theme>\n    <name>noctalia</name>\n  </theme>' "$rc_file"
fi
