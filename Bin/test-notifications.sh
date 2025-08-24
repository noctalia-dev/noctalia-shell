#!/usr/bin/env -S bash

set -euo pipefail

mode="${1:-}" # optional: pass "actions" to test action buttons

if [[ "$mode" == "actions" ]]; then
    echo "Sending a test notification with actions (and waiting for response)..."
    # Uses libnotify's interactive actions with -A and waits (-w) for a result.
    # The identifier we care about is 'open_term' which will trigger opening the terminal.
    action=$(notify-send \
        -a 'Test App' \
        -i utilities-terminal \
        -A open_term='Open Terminal' \
        -A cancel=Cancel \
        -w \
        'Open terminal?' \
        'Click to open your terminal.')

    echo "Selected action: ${action:-<none>}"
    if [[ "$action" == "open_term" ]]; then
        # Try to open the default terminal; ignore errors and disassociate from this shell
        kitty >/dev/null 2>&1 &
    fi
    exit 0
fi

echo "Sending 8 test notifications..."

# Send 8 notifications with numbers
for i in {1..8}; do
    notify-send "Notification $i" "This is test notification number $i of 8"
    sleep 1
done

echo "All notifications sent!"
