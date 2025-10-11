{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.noctalia-shell;
  defaultSettings = builtins.fromJSON (builtins.readFile ../Assets/settings-default.json);

  mergedSettings =
    if cfg.settings == null then
      defaultSettings
    else if builtins.isAttrs cfg.settings then
      lib.recursiveUpdate defaultSettings cfg.settings
    else
      cfg.settings;
in
{
  options.programs.noctalia-shell = {
    enable = lib.mkEnableOption "Noctalia shell configuration";

    settings = lib.mkOption {
      type =
        with lib.types;
        nullOr (oneOf [
          attrs
          str
          path
        ]);
      default = null;
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
      type =
        with lib.types;
        nullOr (oneOf [
          attrs
          str
          path
        ]);
      default = null;
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
  };

  config =
    let
      restart = ''
        ${pkgs.systemd}/bin/systemctl --user try-restart noctalia-shell.service 2>/dev/null || true
      '';
      useApp2Unit = mergedSettings.appLauncher.useApp2Unit or false;
    in
    lib.mkIf cfg.enable {
      home.packages = lib.optional useApp2Unit pkgs.app2unit;

      xdg.configFile = {
        "noctalia/settings.json" = {
          onChange = restart;
        }
        // (
          if builtins.isAttrs mergedSettings then
            { text = builtins.toJSON mergedSettings + "\n"; }
          else if builtins.isString mergedSettings then
            { text = mergedSettings; }
          else
            { source = mergedSettings; }
        );
        "noctalia/colors.json" = lib.mkIf (cfg.colors != null) (
          {
            onChange = restart;
          }
          // (
            if builtins.isAttrs cfg.colors then
              { text = builtins.toJSON cfg.colors; }
            else if builtins.isString cfg.colors then
              { text = cfg.colors; }
            else
              { source = cfg.colors; }
          )
        );
      };
    };
}
