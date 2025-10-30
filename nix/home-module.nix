{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.noctalia-shell;
  defaultSettings = builtins.fromJSON (builtins.readFile ../Assets/settings-default.json);
  extractAttrs = x:
    if builtins.isAttrs x
    then x
    else if builtins.isString x
    then builtins.fromJson x
    else builtins.fromJson (builtins.readFile x);
in {
  options.programs.noctalia-shell = {
    enable = lib.mkEnableOption "Noctalia shell configuration";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      description = "The noctalia-shell package to use";
    };

    settings = lib.mkOption {
      type = with lib.types;
        nullOr (oneOf [
          attrs
          str
          path
        ]);
      default = {};
      apply = x: lib.recursiveUpdate defaultSettings (extractAttrs x);
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
        When provided as an attribute set, it will be deep-merged with
        the default settings.
      '';
    };

    colors = lib.mkOption {
      type = with lib.types;
        nullOr (oneOf [
          attrs
          str
          path
        ]);
      default = {};
      apply = extractAttrs;
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

    app2unit.package = lib.mkOption {
      type = lib.types.package;
      description = ''
        The app2unit package to use when appLauncher.useApp2Unit is enabled.
      '';
    };
  };

  config = let
    restart = ''
      ${pkgs.systemd}/bin/systemctl --user try-restart noctalia-shell.service 2>/dev/null || true
    '';
    useApp2Unit = cfg.settings.appLauncher.useApp2Unit or false;
  in
    lib.mkIf cfg.enable {
      home.packages = lib.optional useApp2Unit cfg.app2unit.package
        ++ lib.optional (cfg.package != null) cfg.package;

      xdg.configFile = {
        "noctalia/settings.json" = {
          onChange = restart;
          text = builtins.toJSON cfg.settings;
        };
        "noctalia/colors.json" = lib.mkIf (cfg.colors != {}) {
          onChange = restart;
          text = builtins.toJSON cfg.colors;
        };
      };
    };
}
