#!/usr/bin/env bash
set -euo pipefail

zathura_instances=$(dbus-send --session \
    --dest=org.freedesktop.DBus \
    --type=method_call \
    --print-reply \
    /org/freedesktop/DBus \
    org.freedesktop.DBus.ListNames |
    grep -o 'org.pwmt.zathura.PID-[0-9]*' || true)

for id in $zathura_instances; do
    dbus-send --session \
        --dest="$id" \
        --type=method_call \
        /org/pwmt/zathura \
        org.pwmt.zathura.ExecuteCommand \
        string:"source"
done
