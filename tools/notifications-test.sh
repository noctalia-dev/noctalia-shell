#!/usr/bin/env -S bash

echo "Sending test notifications..."

notify-send "Notification #1" "A 'low' urgency notification" -u low
sleep 0.5

notify-send "Notification #2" "A 'normal' urgency notification with a smiley 😛 face." -u normal
sleep 0.5

notify-send "Notification #3" "A 'critical' urgency notification with a long timeout" -u critical -t 12000
sleep 0.5

notify-send "Notification #4" "This is test notification with a very long text that will probably break the layout or maybe not? Who knows? Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."
sleep 0.5

notify-send "Notification #5" "A notification with a named icon, should resolve from theme (dialog-information)" -i dialog-information 
sleep 0.5

notify-send "Notification #6" "A notification with an absolute path icon" -i "/usr/share/pixmaps/steam.png" 
sleep 0.5

notify-send "Notification #7" "A notification with an absolute file://path icon" -i "file:///usr/share/pixmaps/steam.png" 
sleep 0.5

# A test notification with actions
gdbus call --session \
          --dest org.freedesktop.Notifications \
          --object-path /org/freedesktop/Notifications \
          --method org.freedesktop.Notifications.Notify \
          "my-app" \
          0 \
          "dialog-question" \
          "Notification #8 - Confirmation Required" \
          "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Do you want to proceed with the action? " \
          "['default', 'OK', 'cancel', 'Cancel', 'maybe', 'Maybe', 'undecided', 'Undecided']" \
          "{}" \
          5000
