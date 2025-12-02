{pkgs, ...}:
pkgs.writeShellScriptBin "noctalia-live-devel" ''
  echo "Stopping noctalia-shell service and starting qs"
  echo "Use qs-noctalia ipc to invoke the dev server or regular service"
  [ -d ~/.config/quickshell/noctalia-shell ] || echo "error: noctalia-shell repo needs to be in ~/.config/quickshell"
  systemctl stop --user noctalia-shell
  trap 'systemctl start --user noctalia-shell; echo "Restarted noctalia-shell service"' EXIT
  qs -p ~/.config/quickshell/noctalia-shell
''
