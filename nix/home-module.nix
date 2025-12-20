{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.noctalia-shell;
  jsonFormat = pkgs.formats.json { };
  tomlFormat = pkgs.formats.toml { };

  generateJson =
    name: value:
    if lib.isString value then
      pkgs.writeText "noctalia-${name}.json" value
    else if builtins.isPath value || lib.isStorePath value then
      value
    else
      jsonFormat.generate "noctalia-${name}.json" value;
in
{
  options.programs.noctalia-shell = {
    enable = lib.mkEnableOption "Noctalia shell configuration";

    systemd.enable = lib.mkEnableOption "Noctalia shell systemd integration";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      description = "The noctalia-shell package to use";
    };

    settings = lib.mkOption {
      type =
        with lib.types;
        oneOf [
          jsonFormat.type
          str
          path
        ];
      default = { };
      example = lib.literalExpression ''
        {
          bar = {
            position = "bottom";
            floating = true;
            backgroundOpacity = 0.95;
          };
          general = {
            animationSpeed = 1.5;
            radiusRatio = 1.2;
          };
          colorSchemes = {
            darkMode = true;
            useWallpaperColors = true;
          };
        }
      '';
      description = ''
        Noctalia shell configuration settings as an attribute set, string
        or filepath, to be written to ~/.config/noctalia/settings.json.
      '';
    };

    colors = lib.mkOption {
      type =
        with lib.types;
        oneOf [
          jsonFormat.type
          str
          path
        ];
      default = { };
      example = lib.literalExpression ''
         {
           mError = "#dddddd";
           mOnError = "#111111";
           mOnPrimary = "#111111";
           mOnSecondary = "#111111";
           mOnSurface = "#828282";
           mOnSurfaceVariant = "#5d5d5d";
           mOnTertiary = "#111111";
           mOutline = "#3c3c3c";
           mPrimary = "#aaaaaa";
           mSecondary = "#a7a7a7";
           mShadow = "#000000";
           mSurface = "#111111";
           mSurfaceVariant = "#191919";
           mTertiary = "#cccccc";
        }
      '';
      description = ''
        Noctalia shell color configuration as an attribute set, string
        or filepath, to be written to ~/.config/noctalia/colors.json.
      '';
    };

    user-templates = lib.mkOption {
      default = { };
      type =
        with lib.types;
        oneOf [
          tomlFormat.type
          str
          path
        ];
      example = lib.literalExpression ''
        {
          templates = {
            neovim = {
              input_path = "~/.config/matugen/templates/template.lua";
              output_path = "~/.config/nvim/generated.lua";
              post_hook = "pkill -SIGUSR1 nvim";
            };
          };
        }
      '';
      description = ''
        Template definitions for Matugen, to be written to ~/.config/noctalia/user-templates.toml.

        This option accepts:
        - a Nix attrset (converted to TOML automatically)
        - a string containing raw TOML
        - a path to an existing TOML file
      '';
    };

    app2unit.package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.app2unit;
      description = ''
        The app2unit package to use when appLauncher.useApp2Unit is enabled.
      '';
    };
  };

  config =
    let
      useApp2Unit = cfg.settings.appLauncher.useApp2Unit or false;
    in
    lib.mkIf cfg.enable {
      systemd.user.services.noctalia-shell = lib.mkIf cfg.systemd.enable {
        Unit = {
          Description = "Noctalia Shell - Wayland desktop shell";
          Documentation = "https://docs.noctalia.dev/docs";
          PartOf = [ config.wayland.systemd.target ];
          After = [ config.wayland.systemd.target ];
          X-Restart-Triggers =
            lib.optional (cfg.settings != { }) config.xdg.configFile."noctalia/settings.json".source
            ++ lib.optional (cfg.colors != { }) config.xdg.configFile."noctalia/colors.json".source
            ++ lib.optional (
              cfg.user-templates != { }
            ) config.xdg.configFile."noctalia/user-templates.toml".source;
        };

        Service = {
          ExecStart = lib.getExe cfg.package;
          Restart = "on-failure";
          Environment = [
            "NOCTALIA_SETTINGS_FALLBACK=%h/.config/noctalia/gui-settings.json"
          ];
        };

        Install.WantedBy = [ config.wayland.systemd.target ];
      };

      home.packages =
        lib.optional useApp2Unit cfg.app2unit.package ++ lib.optional (cfg.package != null) cfg.package;

      xdg.configFile = {
        "noctalia/settings.json" = lib.mkIf (cfg.settings != { }) {
          source = generateJson "settings" cfg.settings;
        };
        "noctalia/colors.json" = lib.mkIf (cfg.colors != { }) {
          source = generateJson "colors" cfg.colors;
        };
        "noctalia/user-templates.toml" = lib.mkIf (cfg.user-templates != { }) {
          source =
            if lib.isString cfg.user-templates then
              pkgs.writeText "noctalia-user-templates.toml" cfg.user-templates
            else if builtins.isPath cfg.user-templates || lib.isStorePath cfg.user-templates then
              cfg.user-templates
            else
              tomlFormat.generate "noctalia-user-templates.toml" cfg.user-templates;
        };
      };

      assertions = [
        {
          assertion = !cfg.systemd.enable || cfg.package != null;
          message = "noctalia-shell: The package option must not be null when systemd service is enabled.";
        }
      ];
    };
}
