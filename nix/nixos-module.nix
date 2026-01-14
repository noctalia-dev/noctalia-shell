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

    mutableRuntimeSettings = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        When enabled, noctalia-shell creates a copy of settings.json named gui-settings.json.
        gui-settings.json is updated with changes made within the GUI, and can be diff-ed against settings.json, which you can read more about here: https://docs.noctalia.dev/getting-started/nixos/#noctalia-settings.
        NOTE: gui-settings.json is not persistent and resets to the value of settings.json when noctalia (re)starts.

        Disable this option if you are NOT managing noctalia settings with nix, so that noctalia-shell would then write to settings.json mutably like in other distros.
      '';
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
        Environment = lib.mkIf cfg.mutableRuntimeSettings [
          "NOCTALIA_SETTINGS_FALLBACK=%h/.config/noctalia/gui-settings.json"
        ];
      };
    };

    environment.systemPackages = [ cfg.package ];
  };
}
