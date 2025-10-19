{
  flake.nixosModules.default = {
    config,
    lib,
    ...
  }: let
    cfg = config.services.noctalia-shell;
  in {
    options.services.noctalia-shell = {
      enable = lib.mkEnableOption "Noctalia shell systemd service";

      package = lib.mkOption {
        type = lib.types.package;
        description = "The noctalia-shell package to use";
      };

      target = lib.mkOption {
        type = lib.types.str;
        default = "graphical-session.target";
        example = "hyprland-session.target";
        description = "The systemd target for the noctalia-shell service.";
      };
    };

    config = lib.mkIf cfg.enable {
      systemd.user.services.noctalia-shell = {
        description = "Noctalia Shell - Wayland desktop shell";
        documentation = ["https://github.com/noctalia-dev/noctalia-shell"];
        after = [cfg.target];
        partOf = [cfg.target];
        wantedBy = [cfg.target];
        restartTriggers = [cfg.package];

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

      environment.systemPackages = [cfg.package];
    };
  };
}
