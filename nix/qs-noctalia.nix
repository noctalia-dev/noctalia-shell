{pkgs, ...}:
pkgs.writeShellScriptBin "qs-noctalia" ''
  if qs list --all|grep /home/|grep noctalia-shell >/dev/null; then
  qs -c noctalia-shell "$@"
  else
  noctalia-shell "$@"
  fi
''
