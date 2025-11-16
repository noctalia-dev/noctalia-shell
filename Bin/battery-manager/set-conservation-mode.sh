#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPPRESS_NOTIFICATIONS=false

print_error() {
    echo -e "$1" >&2
}

print_info() {
    echo -e "$1"
}

send_notification() {
    local urgency="$1"
    local title="$2"
    local message="$3"

    if [ "$SUPPRESS_NOTIFICATIONS" = false ] && command -v notify-send >/dev/null 2>&1; then
        notify-send -u "$urgency" "$title" "$message"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -q|--quiet)
            SUPPRESS_NOTIFICATIONS=true
            shift
            ;;
        -*)
            print_error "Unknown option: $1"
            echo "Usage: $0 [OPTIONS] <number>" >&2
            echo "Options:" >&2
            echo "  -q, --quiet    Suppress notifications" >&2
            exit 1
            ;;
        *)
            CONSERVATION_MODE="$1"
            shift
            ;;
    esac
done

if [ -z "$CONSERVATION_MODE" ]; then
    print_error "Conservation mode value not specified"
    echo "Usage: $0 [OPTIONS] <0|1>" >&2
    echo "Options:" >&2
    echo "  -q, --quiet    Suppress notifications" >&2
    exit 1
fi

if ! [[ "$CONSERVATION_MODE" =~ ^[01]$ ]]; then
    print_error "Invalid argument: must be 0 (disable) or 1 (enable)"
    echo "Usage: $0 [OPTIONS] <0|1>" >&2
    echo "Options:" >&2
    echo "  -q, --quiet    Suppress notifications" >&2
    exit 1
fi

CURRENT_USER="$USER"
if [ -z "$CURRENT_USER" ]; then
    CURRENT_USER="$(whoami)"
fi

BATTERY_MANAGER_PATH="/usr/bin/battery-manager-$CURRENT_USER"

SUCCESS=0
MISSING_FILES=2

if [ ! -f "$BATTERY_MANAGER_PATH" ]; then
    print_error "Battery manager components missing for user $CURRENT_USER!"
    exit $MISSING_FILES
fi

print_info "Setting conservation mode to $CONSERVATION_MODE for user $CURRENT_USER..."

if pkexec "$BATTERY_MANAGER_PATH" "$CONSERVATION_MODE"; then
    if [ "$CONSERVATION_MODE" -eq 1 ]; then
        print_info "Conservation mode ENABLED"
        send_notification "normal" "Battery Conservation Mode" \
            "Battery conservation mode has been enabled"
    else
        print_info "Conservation mode DISABLED"
        send_notification "normal" "Battery Conservation Mode" \
            "Battery conservation mode has been disabled"
    fi
else
    print_error "Failed to set conservation mode"
    send_notification "critical" "Battery Conservation Mode Failed" \
        "Failed to set battery conservation mode to $CONSERVATION_MODE"
    exit 1
fi