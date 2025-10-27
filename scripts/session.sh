#!/bin/bash

# Session script for the greeter
# This script reads session information from the sessions directory

SESSIONS_DIR="$1"

# Function to parse sessions from a directory
parse_sessions() {
    local dir="$1"
    
    if [ -d "$dir" ]; then
        for desktop_file in "$dir"/*.desktop; do
            if [ -f "$desktop_file" ]; then
                # Extract session name and exec
                name=$(grep "^Name=" "$desktop_file" | cut -d'=' -f2 | head -1)
                exec_cmd=$(grep "^Exec=" "$desktop_file" | cut -d'=' -f2 | head -1)
                
                if [ -n "$name" ] && [ -n "$exec_cmd" ]; then
                    # Remove .desktop extension for the identifier
                    identifier=$(basename "$desktop_file" .desktop)
                    echo "$identifier,$name,$exec_cmd"
                fi
            fi
        done
    fi
}

# If a specific sessions directory is provided, use it
if [ -n "$SESSIONS_DIR" ]; then
    parse_sessions "$SESSIONS_DIR"
else
    # Check common session directories
    parse_sessions "/usr/share/wayland-sessions"
    parse_sessions "/usr/share/xsessions"
fi

# If no valid sessions found, provide defaults
if [ ! -d "/usr/share/wayland-sessions" ] && [ ! -d "/usr/share/xsessions" ]; then
    echo "default,Hyprland,hyprland"
    echo "gnome,Gnome,gnome-session"
    echo "kde,KDE Plasma,startplasma-wayland"
    echo "sway,Sway,sway"
fi
