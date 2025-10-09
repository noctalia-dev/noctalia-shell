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
        CONFIG_FILE="$HOME/.config/fuzzel/fuzzel.ini"
        
        # Check if the config file exists.
        if [ -f "$CONFIG_FILE" ]; then
            # Remove any existing theme include line.
            sed -i '/themes/d' "$CONFIG_FILE"
            # Add the new theme include line.
            echo "include=~/.config/fuzzel/themes/noctalia" >> "$CONFIG_FILE"
        else
            echo "Error: fuzzel config file not found at $CONFIG_FILE" >&2
            exit 1
        fi
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