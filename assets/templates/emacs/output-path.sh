#!/usr/bin/env bash
set -euo pipefail
# Emit one absolute path: first existing config root wins (legacy emacsClients order).
: "${HOME?}"
for root in "${HOME}/.config/doom" "${HOME}/.config/emacs" "${HOME}/.emacs.d"; do
  if [[ -d "$root" ]]; then
    printf '%s/themes/noctalia-theme.el\n' "$root"
    exit 0
  fi
done
