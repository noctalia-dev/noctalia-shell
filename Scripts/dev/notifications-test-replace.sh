#!/usr/bin/env bash
# Test script for notification replacement functionality

echo "Testing notification replacement..."
echo ""

# Send initial notification and capture the ID
echo "Step 1: Sending initial notification 'asdf'..."
NOTIF_ID=$(notify-send -p "asdf")
echo "Notification ID: $NOTIF_ID"
echo ""

# Wait a moment for the notification to appear
sleep 1

# Replace the notification
echo "Step 2: Replacing notification $NOTIF_ID with 'test'..."
notify-send -r "$NOTIF_ID" -p "test"
echo ""

echo "The notification should now show 'test' instead of 'asdf'."
echo "If it still shows 'asdf', the replacement is not working."

