#!/usr/bin/env bash

LOG_FILE="/var/log/battery-manager.log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

if [ -z "$1" ]; then
    echo "Error: No battery level provided" >&2
    log_message "ERROR: No battery level provided"
    exit 1
fi

BATTERY_LEVEL="$1"

if ! [[ "$BATTERY_LEVEL" =~ ^[0-9]+$ ]] || [ "$BATTERY_LEVEL" -gt 100 ] || [ "$BATTERY_LEVEL" -lt 0 ]; then
    echo "Error: Invalid battery level. Must be 0-100" >&2
    log_message "ERROR: Invalid battery level: $BATTERY_LEVEL"
    exit 1
fi

SUCCESS_COUNT=0
FAIL_COUNT=0

for path in "${BATTERY_PATHS[@]}"; do
    [[ -z "$path" || "$path" =~ ^# ]] && continue

    if [ -f "$path" ] && [ -w "$path" ]; then
        if echo "$BATTERY_LEVEL" > "$path" 2>/dev/null; then
            echo "Updated: $path"
            log_message "SUCCESS: Updated $path to $BATTERY_LEVEL"
            ((SUCCESS_COUNT++))
        else
            echo "Failed to write: $path" >&2
            log_message "ERROR: Failed to write to $path"
            ((FAIL_COUNT++))
        fi
    else
        echo "Skipped (not found/writable): $path"
        log_message "INFO: Skipped $path (not found or not writable)"
    fi
done

log_message "SUMMARY: Updated $SUCCESS_COUNT file(s), failed $FAIL_COUNT, battery level: $BATTERY_LEVEL"

if [ "$SUCCESS_COUNT" -eq 0 ]; then
    echo "Error: No battery files were updated" >&2
    exit 1
fi

echo "Successfully updated $SUCCESS_COUNT battery file(s)"
exit 0
