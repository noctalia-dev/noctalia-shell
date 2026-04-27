#!/usr/bin/env bash
set -euo pipefail

if [ -w "$HOME/.config/kitty/kitty.conf" ]; then
    kitty +kitten themes --reload-in=all noctalia
else
    kitty +runpy "from kitty.utils import *; reload_conf_in_all_kitties()"
fi

pkill -USR1 kitty >/dev/null 2>&1 || true
