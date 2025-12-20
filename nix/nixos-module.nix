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
      documentation = [ "https://docs.noctalia.dev/docs" ];
      after = [ cfg.target ];
      partOf = [ cfg.target ];
      wantedBy = [ cfg.target ];
      restartTriggers = [ cfg.package ];

      environment = {
        PATH = lib.mkForce null;
      };

      serviceConfig = {
        ExecStart = lib.getExe cfg.package;
        Restart = "on-failure";
        Environment = [
          "NOCTALIA_SETTINGS_FALLBACK=%h/.config/noctalia/gui-settings.json"
        ];
      };
    };

    environment.systemPackages = [ cfg.package ];
  };
}
