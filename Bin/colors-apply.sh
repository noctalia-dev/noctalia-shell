#!/usr/bin/env -S bash

# Ensure exactly one argument is provided.
if [ "$#" -ne 1 ]; then
    # Print usage information to standard error.
    echo "Error: No application specified." >&2
    echo "Usage: $0 {kitty|ghostty|foot|alacritty|wezterm|fuzzel|walker|pywalfox|cava|niri}" >&2
    exit 1
fi

APP_NAME="$1"

# --- Apply theme based on the application name ---
case "$APP_NAME" in
kitty)
    echo "🎨 Applying 'noctalia' theme to kitty..."
    KITTY_CONF="$HOME/.config/kitty/kitty.conf"
    if [ -w "$KITTY_CONF" ]; then
        kitty +kitten themes --reload-in=all noctalia
    else
        kitty +runpy "from kitty.utils import *; reload_conf_in_all_kitties()"
    fi
    ;;

ghostty)
    echo "🎨 Applying 'noctalia' theme to ghostty..."
    CONFIG_FILE="$HOME/.config/ghostty/config"
    # Check if the config file exists before trying to modify it.
    if [ -f "$CONFIG_FILE" ]; then
        # Check if theme is already set to noctalia
        if grep -q "^theme = noctalia" "$CONFIG_FILE"; then
            echo "Theme already set to noctalia, skipping modification."
        else
            # Remove any existing theme include line to prevent duplicates.
            sed -i '/theme/d' "$CONFIG_FILE"
            # Add the new theme include line to the end of the file.
            echo "theme = noctalia" >>"$CONFIG_FILE"
        fi
        pkill -SIGUSR2 ghostty
    else
        echo "Error: ghostty config file not found at $CONFIG_FILE" >&2
        exit 1
    fi
    ;;

foot)
    echo "🎨 Applying 'noctalia' theme to foot..."
    CONFIG_FILE="$HOME/.config/foot/foot.ini"

    # Check if the config file exists, create it if it doesn't.
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Config file not found, creating $CONFIG_FILE..."
        # Create the config directory if it doesn't exist
        mkdir -p "$(dirname "$CONFIG_FILE")"
        # Create the config file with the noctalia theme
        cat >"$CONFIG_FILE" <<'EOF'
[main]
include=~/.config/foot/themes/noctalia
EOF
        echo "Created new config file with noctalia theme."
    else
        # Check if theme is already set to noctalia
        if grep -q "include.*noctalia" "$CONFIG_FILE"; then
            echo "Theme already set to noctalia, skipping modification."
        else
            # Remove any existing theme include line to prevent duplicates.
            sed -i '/include=.*themes/d' "$CONFIG_FILE"
            if grep -q '^\[main\]' "$CONFIG_FILE"; then
                # Insert the include line after the existing [main] section header
                sed -i '/^\[main\]/a include=~/.config/foot/themes/noctalia' "$CONFIG_FILE"
            else
                # If [main] doesn't exist, create it at the beginning with the include
                sed -i '1i [main]\ninclude=~/.config/foot/themes/noctalia\n' "$CONFIG_FILE"
            fi
        fi
    fi
    ;;

alacritty)
    echo "🎨 Applying 'noctalia' theme to alacritty..."
    CONFIG_FILE="$HOME/.config/alacritty/alacritty.toml"

    # Check if the config file exists.
    if [ -f "$CONFIG_FILE" ]; then
        # Check if theme is already imported
        if grep -q 'import = \[.*"themes/noctalia.toml".*\]' "$CONFIG_FILE"; then
            echo "Theme already set to noctalia, skipping modification."
        else
            # Check if [general] section exists
            if grep -q '^\[general\]' "$CONFIG_FILE"; then
                # Check if import line exists under [general]
                if sed -n '/^\[general\]/,/^\[/p' "$CONFIG_FILE" | grep -q '^import = \['; then
                    # Replace existing import line with noctalia theme
                    sed -i '/^\[general\]/,/^\[/{s|^import = \[.*\]|import = ["themes/noctalia.toml"]|}' "$CONFIG_FILE"
                else
                    # Add import line after [general] section
                    sed -i '/^\[general\]/a import = ["themes/noctalia.toml"]' "$CONFIG_FILE"
                fi
            else
                # Create [general] section with import at the beginning of the file
                sed -i '1i [general]\nimport = ["themes/noctalia.toml"]\n' "$CONFIG_FILE"
            fi
        fi
    else
        echo "Error: alacritty config file not found at $CONFIG_FILE" >&2
        exit 1
    fi
    ;;

wezterm)
    echo "🎨 Applying 'noctalia' theme to wezterm..."
    CONFIG_FILE="$HOME/.config/wezterm/wezterm.lua"
    WEZTERM_SCHEME_LINE='config.color_scheme = "Noctalia"'

    # Check if the config file exists.
    if [ -f "$CONFIG_FILE" ]; then

        # Check if theme is already set to Noctalia (matches 'Noctalia' or "Noctalia")
        if grep -q "^\s*config\.color_scheme\s*=\s*['\"]Noctalia['\"]\s*" "$CONFIG_FILE"; then
            echo "Theme already set to Noctalia, skipping modification."
        else
            # Not set to Noctalia. Check if *any* color_scheme line exists.
            if grep -q '^\s*config\.color_scheme\s*=' "$CONFIG_FILE"; then
                # It exists, so we replace it with our desired line.
                sed -i "s|^\(\s*config\.color_scheme\s*=\s*\).*$|\1\"Noctalia\"|" "$CONFIG_FILE"
            else
                # It doesn't exist, so we add it before the 'return config' line.
                if grep -q '^\s*return\s*config' "$CONFIG_FILE"; then
                    # 'return config' exists. Insert the line before it.
                    sed -i "/^\s*return\s*config/i\\$WEZTERM_SCHEME_LINE" "$CONFIG_FILE"
                else
                    # This is a problem. We can't find the insertion point.
                    echo "Warning: 'config.color_scheme' not set and 'return config' line not found." >&2
                    echo "         Make sure $CONFIG_FILE is correct: https://wezterm.org/config/files.html" >&2
                fi
            fi
        fi
        # touching the config file fools wezterm into reloading it
        touch "$CONFIG_FILE"
    else
        echo "Error: wezterm.lua not found at $CONFIG_FILE" >&2
        echo "Instructions to create it: https://wezterm.org/config/files.html" >&2
        exit 1
    fi
    ;;

fuzzel)
    echo "🎨 Applying 'noctalia' theme to fuzzel..."
    CONFIG_FILE="$HOME/.config/fuzzel/fuzzel.ini"

    # Check if the config file exists, create it if it doesn't.
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Config file not found, creating $CONFIG_FILE..."
        # Create the config directory if it doesn't exist
        mkdir -p "$(dirname "$CONFIG_FILE")"
        # Create the config file with the noctalia theme
        cat >"$CONFIG_FILE" <<'EOF'
include=~/.config/fuzzel/themes/noctalia
EOF
        echo "Created new config file with noctalia theme."
    else
        # Check if theme is already set to noctalia
        if grep -q "include=~/.config/fuzzel/themes/noctalia" "$CONFIG_FILE"; then
            echo "Theme already set to noctalia, skipping modification."
        else
            # Remove any existing theme include line.
            sed -i '/themes/d' "$CONFIG_FILE"
            # Add the new theme include line.
            echo "include=~/.config/fuzzel/themes/noctalia" >>"$CONFIG_FILE"
        fi
    fi
    ;;

walker)
    echo "🎨 Applying 'noctalia' theme to walker..."
    CONFIG_FILE="$HOME/.config/walker/config.toml"

    # Check if the config file exists.
    if [ -f "$CONFIG_FILE" ]; then
        # Check if theme is already set to noctalia
        if grep -q '^theme = "noctalia"' "$CONFIG_FILE"; then
            echo "Theme already set to noctalia, skipping modification."
        else
            # Check if a theme line exists and replace it, otherwise append
            if grep -q '^theme = ' "$CONFIG_FILE"; then
                sed -i 's/^theme = .*/theme = "noctalia"/' "$CONFIG_FILE"
            else
                echo 'theme = "noctalia"' >>"$CONFIG_FILE"
            fi
        fi
    else
        echo "Error: walker config file not found at $CONFIG_FILE" >&2
        exit 1
    fi
    ;;

vicinae)
    echo "🎨 Applying noctalia theme to vicinae..."
    # Apply the theme
    vicinae theme set noctalia
    ;;

pywalfox)
    echo "🎨 Updating pywalfox themes..."
    pywalfox update
    ;;

cava)
    echo "🎨 Applying 'noctalia' theme to cava..."
    CONFIG_FILE="$HOME/.config/cava/config"
    THEME_MODIFIED=false

    # Check if the config file exists.
    if [ -f "$CONFIG_FILE" ]; then
        # Check if [color] section exists
        if grep -q '^\[color\]' "$CONFIG_FILE"; then
            echo "[color] section found, checking theme setting..."
            # Check if theme is already set to noctalia under [color]
            if sed -n '/^\[color\]/,/^\[/p' "$CONFIG_FILE" | grep -q '^theme = "noctalia"'; then
                echo "Theme already set to noctalia under [color], skipping modification."
            else
                # Check if theme line exists under [color] section
                if sed -n '/^\[color\]/,/^\[/p' "$CONFIG_FILE" | grep -q '^theme = '; then
                    # Replace existing theme line under [color]
                    sed -i '/^\[color\]/,/^\[/{s/^theme = .*/theme = "noctalia"/}' "$CONFIG_FILE"
                    THEME_MODIFIED=true
                else
                    # Add theme line after [color]
                    sed -i '/^\[color\]/a theme = "noctalia"' "$CONFIG_FILE"
                    THEME_MODIFIED=true
                fi
            fi
        else
            echo "[color] section not found, adding it with theme..."
            # Add [color] section with theme at the end of file
            echo "" >>"$CONFIG_FILE"
            echo "[color]" >>"$CONFIG_FILE"
            echo 'theme = "noctalia"' >>"$CONFIG_FILE"
            THEME_MODIFIED=true
        fi

        # Reload cava if it's running, but only if it's not using stdin config
        if pgrep -f cava >/dev/null; then
            # Check if Cava is running with -p /dev/stdin (managed by CavaService)
            if pgrep -af cava | grep -q -- "-p.*stdin"; then
                echo "Cava is managed by CavaService (stdin config), skipping reload signal."
                echo "✅ Theme file updated. CavaService will use the theme on next restart."
            else
                echo "Reloading cava configuration..."
                pkill -USR1 cava
                echo "✅ Cava reloaded successfully"
            fi
        else
            if [ "$THEME_MODIFIED" = true ]; then
                echo "✅ Configuration updated. Start cava to see the changes."
            else
                echo "✅ Configuration already correct."
            fi
        fi
    else
        echo "Error: cava config file not found at $CONFIG_FILE" >&2
        exit 1
    fi
    ;;

niri)
    echo "🎨 Applying 'noctalia' theme to niri..."
    CONFIG_FILE="$HOME/.config/niri/config.kdl"
    INCLUDE_LINE='include "./noctalia.kdl"'

    # Check if the config file exists.
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Config file not found, creating $CONFIG_FILE..."
        mkdir -p "$(dirname "$CONFIG_FILE")"
        echo "$INCLUDE_LINE" >"$CONFIG_FILE"
        echo "Created new config file with noctalia theme."
    else
        # Check if include line already exists
        if grep -qF "$INCLUDE_LINE" "$CONFIG_FILE"; then
            echo "Theme already included, skipping modification."
        else
            # Add the include line to the end of the file
            echo "$INCLUDE_LINE" >>"$CONFIG_FILE"
            echo "✅ Added noctalia theme include to config."
        fi
    fi
    ;;

hyprland)
    echo "🎨 Applying 'noctalia' theme to Hyprland..."
    CONFIG_FILE="$HOME/.config/hypr/hyprland.conf"
    INCLUDE_LINE="source = ~/.config/hypr/noctalia/noctalia-colors.conf"

    # Check if the config file exists.
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Config file not found, creating $CONFIG_FILE..."
        mkdir -p "$(dirname "$CONFIG_FILE")"
        echo "$INCLUDE_LINE" >"$CONFIG_FILE"
        echo "Created new config file with noctalia theme."
    else
        # Check if include line already exists
        if grep -qF "$INCLUDE_LINE" "$CONFIG_FILE"; then
            echo "Theme already included, skipping modification."
        else
            # Add the include line to the end of the file
            echo "$INCLUDE_LINE" >>"$CONFIG_FILE"
            echo "✅ Added noctalia theme include to config."
        fi
    fi
    ;;

mango)
    echo "🎨 Applying 'noctalia' theme to mango..."
    CONFIG_DIR="$HOME/.config/mango"
    MAIN_CONFIG="$CONFIG_DIR/config.conf"
    THEME_FILE="$CONFIG_DIR/noctalia.conf"
    BACKUP_FILE="$CONFIG_DIR/theme.conf.bak"
    # This sources the noctalia theme file
    SOURCE_LINE="source = $THEME_FILE"

    # Color variables that should be moved to theme file
    COLOR_VARS="shadowscolor|rootcolor|bordercolor|focuscolor|maximizescreencolor|urgentcolor|scratchpadcolor|globalcolor|overlaycolor"

    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR"

    # Check if theme is already sourced in main config
    if [ -f "$MAIN_CONFIG" ] && grep -qF "$SOURCE_LINE" "$MAIN_CONFIG"; then
        echo "Theme already set to noctalia, skipping modification."
    else
        # First-time setup: backup and remove legacy color definitions
        echo "Setting up noctalia theme for the first time..."

        # Scan all .conf files in config directory for legacy color variables
        FOUND_LEGACY=false
        for conf_file in "$CONFIG_DIR"/*.conf; do
            # Skip if no .conf files exist or if it's the theme file itself
            [ -e "$conf_file" ] || continue
            [ "$conf_file" = "$THEME_FILE" ] && continue

            # Check if this file contains any color variable definitions
            if grep -qE "^($COLOR_VARS)\s*=" "$conf_file"; then
                FOUND_LEGACY=true
                echo "Found legacy colors in $(basename "$conf_file"), backing up..."

                # Extract and append color definitions to backup file
                grep -E "^($COLOR_VARS)\s*=" "$conf_file" >>"$BACKUP_FILE"

                # Remove color definitions from original file
                sed -i -E "/^($COLOR_VARS)\s*=/d" "$conf_file"
            fi
        done

        if [ "$FOUND_LEGACY" = true ]; then
            echo "✅ Legacy color definitions backed up to $(basename "$BACKUP_FILE")"
        fi

        # Add source line to main config
        if [ -f "$MAIN_CONFIG" ]; then
            echo "" >>"$MAIN_CONFIG"
            echo "# This sources the noctalia theme" >>"$MAIN_CONFIG"
            echo "$SOURCE_LINE" >>"$MAIN_CONFIG"
        else
            echo "# This sources the noctalia theme" >"$MAIN_CONFIG"
            echo "$SOURCE_LINE" >>"$MAIN_CONFIG"
        fi

        echo "✅ Added noctalia theme to config."
    fi

    # Trigger live reload
    if command -v mmsg >/dev/null 2>&1; then
        mmsg -s -d reload_config
        echo "✅ Configuration reloaded."
    else
        echo "Warning: mmsg command not found, manual restart may be needed." >&2
    fi
    ;;

*)
    # Handle unknown application names.
    echo "Error: Unknown application '$APP_NAME'." >&2
    exit 1
    ;;
esac

echo "✅ Command sent for $APP_NAME."
