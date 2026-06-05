#!/usr/bin/env bash
set -euo pipefail
# Emit one absolute path: first existing config root wins (legacy emacsClients order).
: "${HOME?}"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
for root in "${config_dir}/doom" "${config_dir}/emacs" "${HOME}/.emacs.d"; do
  if [[ -d "$root" ]]; then
    printf '%s/themes/noctalia-theme.el\n' "$root"
    exit 0
  fi
done
