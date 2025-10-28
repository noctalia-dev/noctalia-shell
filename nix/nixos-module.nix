{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.noctalia-shell;
  batteryCfg = cfg.batteryManager;

  # Backend script that does the actual work
  battery-manager-backend = pkgs.writeShellScript "battery-manager-backend" ''
    set -e
    if ! [[ "$1" =~ ^[0-9]+$ ]] || [ "$1" -gt 100 ] || [ "$1" -lt 0 ]; then
        # Use logger for better system integration
        ${pkgs.util-linux}/bin/logger -t battery-manager "Error: Invalid battery level specified: "
        exit 1
    fi

    BATTERY_LEVEL="$1"
    FOUND_PATH=false

    for path in ${lib.escapeShellArgs batteryCfg.paths}; do
      if [ -w "$path" ]; then
        echo "$BATTERY_LEVEL" > "$path"
        ${pkgs.util-linux}/bin/logger -t battery-manager "Set battery threshold to $BATTERY_LEVEL% on $path"
        FOUND_PATH=true
        break
      fi
    done

    if [ "$FOUND_PATH" = false ]; then
        ${pkgs.util-linux}/bin/logger -t battery-manager "Error: No writable battery threshold path found."
        exit 3 # unsupported hardware
    fi
  '';

  # Frontend script that the user runs
  battery-manager-frontend = pkgs.writeShellApplication {
    name = "set-battery-threshold";
    runtimeInputs = [ pkgs.libnotify ];
    text = ''
      SUPPRESS_NOTIFICATIONS=false
      BATTERY_LEVEL=""

      print_error() {
          echo -e "$1" >&2
      }

      send_notification() {
          local urgency="$1"
          local title="$2"
          local message="$3"
          if [ "$SUPPRESS_NOTIFICATIONS" = false ]; then
              "${pkgs.libnotify}/bin/notify-send" -u "$urgency" "$title" "$message"
          fi
      }

      if [ "$#" -eq 0 ]; then
          print_error "Error: Battery level not specified."
          print_error "Usage: $0 [OPTIONS] <number>"
          exit 1
      fi

      while [[ $# -gt 0 ]]; do
          case "$1" in
              -q|--quiet)
                  SUPPRESS_NOTIFICATIONS=true
                  shift
                  ;;
              *)
                  BATTERY_LEVEL="$1"
                  shift
                  ;;
          esac
      done

      if ! [[ "$BATTERY_LEVEL" =~ ^[0-9]+$ ]] || [ "$BATTERY_LEVEL" -gt 100 ] || [ "$BATTERY_LEVEL" -lt 0 ]; then
          print_error "Error: Battery level must be a number between 0-100"
          exit 1
      fi

      echo "Setting battery threshold to $BATTERY_LEVEL%..."

      pkexec /run/wrappers/bin/battery-manager-backend "$BATTERY_LEVEL"
      BACKEND_EXIT=$?

      if [ $BACKEND_EXIT -eq 0 ]; then
        echo "Successfully set battery charging threshold to $BATTERY_LEVEL%."
        send_notification "normal" "Battery Threshold Updated" "Threshold set to $BATTERY_LEVEL%"
      else
        print_error "Error: Failed to set battery charging threshold."
        send_notification "critical" "Battery Threshold Failed" "Failed to set battery charging threshold to $BATTERY_LEVEL%."
        exit $BACKEND_EXIT
      fi
    '';
  };
in
{
  options.services.noctalia-shell = {
    enable = lib.mkEnableOption "Noctalia shell systemd service";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The noctalia-shell package to use";
    };

    target = lib.mkOption {
      type = lib.types.str;
      default = "graphical-session.target";
      description = "The systemd target for the noctalia-shell service.";
    };

    batteryManager = {
      enable = lib.mkEnableOption "Noctalia Battery Manager";
      group = lib.mkOption {
        type = lib.types.str;
        default = "wheel";
        description = "Group that is allowed to set the battery threshold.";
      };
      paths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "/sys/class/power_supply/BAT0/charge_control_end_threshold"
          "/sys/class/power_supply/BAT1/charge_control_end_threshold"
          "/sys/class/power_supply/BAT0/charge_stop_threshold"
          "/sys/class/power_supply/BAT1/charge_stop_threshold"
        ];
        description = "List of paths to check for battery charge threshold control.";
      };
    };
  };

  config = lib.mkIf (cfg.enable || batteryCfg.enable) {
    environment.systemPackages =
      [ ]
      ++ lib.optional cfg.enable cfg.package
      ++ lib.optional batteryCfg.enable battery-manager-frontend;

    services.noctalia-shell.batteryManager = lib.mkIf batteryCfg.enable {
      # This is a placeholder to ensure the structure is valid if we add more options
    };

    security.wrappers = lib.mkIf batteryCfg.enable {
      battery-manager-backend = {
        owner = "root";
        group = "root";
        setuid = true; # Use setuid wrapper for pkexec
        source = "${battery-manager-backend}";
      };
    };

    security.polkit.extraConfig = lib.mkIf batteryCfg.enable ''
      polkit.addRule(function(action, subject) {
        // Match the secure wrapper path
        if (action.id == "org.freedesktop.policykit.exec" &&
            action.lookup("program") == "/run/wrappers/bin/battery-manager-backend" &&
            subject.isInGroup("${batteryCfg.group}")) {
          return polkit.Result.YES;
        }
      });
    '';

    systemd.services.reload-polkit-noctalia = lib.mkIf batteryCfg.enable {
      description = "Reload polkit rules when noctalia battery manager changes";
      after = [ "polkit.service" ];
      wants = [ "polkit.service" ];
      serviceConfig.Type = "oneshot";
      serviceConfig.ExecStart = "${pkgs.systemd}/bin/systemctl reload polkit.service";
      wantedBy = [ "multi-user.target" ];
    };

    systemd.user.services.noctalia-shell = lib.mkIf cfg.enable {
      description = "Noctalia Shell - Wayland desktop shell";
      documentation = [ "https://github.com/noctalia-dev/noctalia-shell" ];
      after = [ cfg.target ];
      partOf = [ cfg.target ];
      wantedBy = [ cfg.target ];
      restartTriggers = [ cfg.package ];
      environment = {
        PATH = lib.mkForce null;
      };
      unitConfig = {
        StartLimitIntervalSec = 60;
        StartLimitBurst = 3;
      };
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/noctalia-shell";
        Restart = "on-failure";
        RestartSec = 3;
        TimeoutStartSec = 10;
        TimeoutStopSec = 5;
        Environment = [
          "NOCTALIA_SETTINGS_FALLBACK=%h/.config/noctalia/gui-settings.json"
        ];
      };
    };
  };
}
