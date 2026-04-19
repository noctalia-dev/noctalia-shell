{
  config,
  lib,
  ...
}:
let
  cfg = config.services.noctalia-shell;
in
{
  options.services.noctalia-shell = {
    enable = lib.mkEnableOption "Noctalia shell";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The noctalia-shell package to use";
    };

    systemd = {
      enable = lib.mkEnableOption "Noctalia shell systemd service";

      target = lib.mkOption {
        type = lib.types.str;
        default = "graphical-session.target";
        example = "hyprland-session.target";
        description = "The systemd target for the noctalia-shell service.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.noctalia-shell = lib.mkIf cfg.systemd.enable {
      description = "Noctalia Shell - Wayland desktop shell";
      documentation = [ "https://docs.noctalia.dev" ];
      after = [ cfg.systemd.target ];
      partOf = [ cfg.systemd.target ];
      wantedBy = [ cfg.systemd.target ];
      restartTriggers = [ cfg.package ];

      environment = {
        PATH = lib.mkForce null;
      };

      serviceConfig = {
        ExecStart = lib.getExe cfg.package;
        Restart = "on-failure";
      };
    };

    environment.systemPackages = [ cfg.package ];
  };
}
