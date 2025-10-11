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
            BATTERY_LEVEL="$1"
            shift
            ;;
    esac
done

if [ -z "$BATTERY_LEVEL" ]; then
    print_error "Battery level not specified"
    echo "Usage: $0 [OPTIONS] <number>" >&2
    echo "Options:" >&2
    echo "  -q, --quiet    Suppress notifications" >&2
    exit 1
fi

if ! [[ "$BATTERY_LEVEL" =~ ^[0-9]+$ ]] || [ "$BATTERY_LEVEL" -gt 100 ] || [ "$BATTERY_LEVEL" -lt 0 ]; then
    print_error "Battery level must be a number between 0-100"
    echo "Usage: $0 [OPTIONS] <number>" >&2
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

print_info "Setting battery charging threshold to $BATTERY_LEVEL% for user $CURRENT_USER..."

if pkexec "$BATTERY_MANAGER_PATH" "$BATTERY_LEVEL"; then
    print_info "Battery charging threshold set to $BATTERY_LEVEL%"
    send_notification "normal" "Battery Threshold Updated" \
        "Battery charging threshold has been set to $BATTERY_LEVEL%"
else
    print_error "Failed to set battery charging threshold"
    send_notification "critical" "Battery Threshold Failed" \
        "Failed to set battery charging threshold to $BATTERY_LEVEL%"
    exit 1
fi
