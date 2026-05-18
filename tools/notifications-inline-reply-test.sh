#!/usr/bin/env -S bash
echo "Sending inline reply test notifications..."

# Test 1: Simple inline reply notification
gdbus call --session \
          --dest org.freedesktop.Notifications \
          --object-path /org/freedesktop/Notifications \
          --method org.freedesktop.Notifications.Notify \
          "Thunderbird Test" \
          0 \
          "thunderbird" \
          "New Message from Alice" \
          "Hey! Are you available for a quick call? I have some questions about the project." \
          "['inline-reply', 'Reply', 'mark-read', 'Mark as Read', 'delete', 'Delete']" \
          "{}" \
          10000

sleep 1

# Test 2: Inline reply with other actions
gdbus call --session \
          --dest org.freedesktop.Notifications \
          --object-path /org/freedesktop/Notifications \
          --method org.freedesktop.Notifications.Notify \
          "Chat App" \
          0 \
          "chat-app" \
          "Bob sent you a message" \
          "Can you review the PR when you get a chance?" \
          "['inline-reply', 'Type a reply...', 'default', 'Open Chat', 'snooze', 'Snooze']" \
          "{}" \
          10000

