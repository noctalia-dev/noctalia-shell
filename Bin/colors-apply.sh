#!/usr/bin/env -S bash


# Ensure exactly one argument is provided.
if [ "$#" -ne 1 ]; then
    # Print usage information to standard error.
    echo "Error: No application specified." >&2
    echo "Usage: $0 {kitty|ghostty|foot|fuzzel|pywalfox}" >&2
    exit 1
fi

APP_NAME="$1"

# --- Apply theme based on the application name ---
case "$APP_NAME" in
    kitty)
        echo "🎨 Applying 'noctalia' theme to kitty..."
        kitty +kitten themes --reload-in=all noctalia
        ;;

    ghostty)
        echo "🎨 Applying 'noctalia' theme to ghostty..."
        CONFIG_FILE="$HOME/.config/ghostty/config"
        # Check if the config file exists before trying to modify it.
        if [ -f "$CONFIG_FILE" ]; then
            # Remove any existing theme include line to prevent duplicates.
            sed -i '/theme/d' "$CONFIG_FILE"
            # Add the new theme include line to the end of the file.
            echo "theme = noctalia" >> "$CONFIG_FILE"
            pkill -SIGUSR2 ghostty
        else
            echo "Error: foot config file not found at $CONFIG_FILE" >&2
            exit 1
        fi
        ;;

    foot)
        echo "🎨 Applying 'noctalia' theme to foot..."
        CONFIG_FILE="$HOME/.config/foot/foot.ini"
        
        # Check if the config file exists before trying to modify it.
        if [ -f "$CONFIG_FILE" ]; then
            # Remove any existing theme include line to prevent duplicates.
            sed -i '/themes/d' "$CONFIG_FILE"
            # Add the new theme include line to the end of the file.
            echo "include=~/.config/foot/themes/noctalia" >> "$CONFIG_FILE"
        else
            echo "Error: foot config file not found at $CONFIG_FILE" >&2
            exit 1
        fi
        ;;

    fuzzel)
        echo "🎨 Applying 'noctalia' theme to fuzzel..."
        CONFIG_DIR="$HOME/.config/fuzzel"
        CONFIG_FILE="$CONFIG_DIR/fuzzel.ini"

        # Check if fuzzel is even installed (don't error if not)
        if ! command -v fuzzel &> /dev/null; then
            echo "⚠️  fuzzel not installed, skipping theme application"
            exit 0
        fi

        # Create config directory if it doesn't exist
        if [ ! -d "$CONFIG_DIR" ]; then
            mkdir -p "$CONFIG_DIR"
        fi

        # Check if the config file exists, create if not.
        if [ ! -f "$CONFIG_FILE" ]; then
            echo "# Fuzzel config file" > "$CONFIG_FILE"
        fi

        # Remove any existing theme include line.
        sed -i '/themes/d' "$CONFIG_FILE"
        # Add the new theme include line.
        echo "include=~/.config/fuzzel/themes/noctalia" >> "$CONFIG_FILE"
        ;;

    pywalfox)
        echo "🎨 Updating pywalfox themes..."
        pywalfox update
        ;;

    *)
        # Handle unknown application names.
        echo "Error: Unknown application '$APP_NAME'." >&2
        exit 1
        ;;
esac

echo "✅ Command sent for $APP_NAME."

        # lines.push("post_hook = \"grep -q '^theme *= *' ~/.config/ghostty/config; and sed -i 's/^theme *= *.*/theme = noctalia/' ~/.config/ghostty/config; or echo 'theme = noctalia' >> ~/.config/ghostty/config; and pkill -SIGUSR2 ghostty\"")