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
            # Check if theme is already set to noctalia
            if grep -q "^theme = noctalia" "$CONFIG_FILE"; then
                pkill -SIGUSR2 ghostty
                echo "Theme already set to noctalia, skipping modification."
            else
                # Remove any existing theme include line to prevent duplicates.
                sed -i '/theme/d' "$CONFIG_FILE"
                # Add the new theme include line to the end of the file.
                echo "theme = noctalia" >> "$CONFIG_FILE"
                pkill -SIGUSR2 ghostty
            fi
        else
            echo "Error: ghostty config file not found at $CONFIG_FILE" >&2
            exit 1
        fi
        ;;

    foot)
        echo "🎨 Applying 'noctalia' theme to foot..."
        CONFIG_FILE="$HOME/.config/foot/foot.ini"
        
        # Check if the config file exists before trying to modify it.
        if [ -f "$CONFIG_FILE" ]; then
            # Check if theme is already set to noctalia
            if grep -q "include=~/.config/foot/themes/noctalia" "$CONFIG_FILE"; then
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
            # Check if theme is already set to noctalia
            if grep -q "include=~/.config/fuzzel/themes/noctalia" "$CONFIG_FILE"; then
                echo "Theme already set to noctalia, skipping modification."
            else
                # Remove any existing theme include line.
                sed -i '/themes/d' "$CONFIG_FILE"
                # Add the new theme include line.
                echo "include=~/.config/fuzzel/themes/noctalia" >> "$CONFIG_FILE"
            fi
        else
            echo "Error: fuzzel config file not found at $CONFIG_FILE" >&2
            exit 1
        fi
        ;;

    vicinae)
        echo "🎨 Applying 'matugen' theme to vicinae..."
        # Apply the theme 
        vicinae theme set matugen
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
