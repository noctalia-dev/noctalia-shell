{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.noctalia-shell;
  cfgWlp = cfg.waylivepaper;
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
              input_path = "~/.config/noctalia/templates/template.lua";
              output_path = "~/.config/nvim/generated.lua";
              post_hook = "pkill -SIGUSR1 nvim";
            };
          };
        }
      '';
      description = ''
        Template definitions for Noctalia, to be written to ~/.config/noctalia/user-templates.toml.

        This option accepts:
        - a Nix attrset (converted to TOML automatically)
        - a string containing raw TOML
        - a path to an existing TOML file
      '';
    };

    plugins = lib.mkOption {
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
          sources = [
            {
              enabled = true;
              name = "Noctalia Plugins";
              url = "https://github.com/noctalia-dev/noctalia-plugins";
            }
          ];
          states = {
            catwalk = {
              enabled = true;
              sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
            };
          };
          version = 2;
        }
      '';
      description = ''
        Noctalia shell plugin configuration as an attribute set, string
        or filepath, to be written to ~/.config/noctalia/plugins.json.
      '';
    };

    pluginSettings = lib.mkOption {
      type =
        with lib.types;
        attrsOf (oneOf [
          jsonFormat.type
          str
          path
        ]);
      default = { };
      example = lib.literalExpression ''
        {
          catwalk = {
            minimumThreshold = 25;
            hideBackground = true;
          };
        }
      '';
      description = ''
        Each plugin’s settings as an attribute set, string
        or filepath, to be written to ~/.config/noctalia/plugins/plugin-name/settings.json.
      '';
    };

    waylivepaper = {
      enable = lib.mkEnableOption "projectM milkdrop visualizer as desktop and lockscreen background";

      presetsSource = lib.mkOption {
        type = lib.types.path;
        description = ''
          Directory of .milk/.prjm presets symlinked into
          $XDG_DATA_HOME/waylivepaper/presets. Default is the
          presets-cream-of-the-crop pack bundled with the noctalia-shell flake.
        '';
      };

      darken = lib.mkOption {
        type = lib.types.float;
        default = 0.7;
        description = "Black overlay opacity (0.0–1.0) applied on the desktop and lockscreen background.";
      };

      presetInterval = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        example = 120;
        description = "Seconds between random preset switches. null → default (120s).";
      };

      fps = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        example = 30;
        description = "Target frame rate. null → default (30).";
      };

      mesh = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "32x24";
        description = "projectM warp mesh resolution as WxH. null → default (24x18).";
      };

      audioSource = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "alsa_output.pci-0000_00_1f.3.analog-stereo.monitor";
        description = "PulseAudio source name. null → auto-detect default monitor.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.mkIf cfg.systemd.enable [
      ''
        Running noctalia-shell as a systemd service has been deprecated!
        See https://docs.noctalia.dev/getting-started/nixos/#running-the-shell for details.
      ''
    ];

    systemd.user.services.noctalia-shell = lib.mkIf cfg.systemd.enable {
      Unit = {
        Description = "Noctalia Shell - Wayland desktop shell";
        Documentation = "https://docs.noctalia.dev";
        PartOf = [ config.wayland.systemd.target ];
        After = [ config.wayland.systemd.target ];
        X-Restart-Triggers =
          lib.optional (cfg.settings != { }) "${config.xdg.configFile."noctalia/settings.json".source}"
          ++ lib.optional (cfg.colors != { }) "${config.xdg.configFile."noctalia/colors.json".source}"
          ++ lib.optional (cfg.plugins != { }) "${config.xdg.configFile."noctalia/plugins.json".source}"
          ++ lib.optional (
            cfg.user-templates != { }
          ) "${config.xdg.configFile."noctalia/user-templates.toml".source}"
          ++ lib.mapAttrsToList (
            name: _: "${config.xdg.configFile."noctalia/plugins/${name}/settings.json".source}"
          ) cfg.pluginSettings;
      };

      Service = {
        ExecStart = lib.getExe cfg.package;
        Restart = "on-failure";
      };

      Install.WantedBy = [ config.wayland.systemd.target ];
    };

    home.packages =
      lib.optional (cfg.package != null) cfg.package;

    xdg.configFile = {
      "noctalia/settings.json" = lib.mkIf (cfg.settings != { }) {
        source = generateJson "settings" cfg.settings;
      };
      "noctalia/colors.json" = lib.mkIf (cfg.colors != { }) {
        source = generateJson "colors" cfg.colors;
      };
      "noctalia/plugins.json" = lib.mkIf (cfg.plugins != { }) {
        source = generateJson "plugins" cfg.plugins;
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
    }
    // lib.mapAttrs' (
      name: value:
      lib.nameValuePair "noctalia/plugins/${name}/settings.json" {
        source = generateJson "${name}-settings" value;
      }
    ) cfg.pluginSettings;

    # Symlink the presets pack into XDG_DATA_HOME so ProjectMService can
    # find them at ~/.local/share/waylivepaper/presets at runtime.
    xdg.dataFile."waylivepaper/presets" = lib.mkIf cfgWlp.enable {
      source = cfgWlp.presetsSource;
    };

    assertions = [
      {
        assertion = !cfg.systemd.enable || cfg.package != null;
        message = "noctalia-shell: The package option must not be null when systemd service is enabled.";
      }
      {
        assertion = !cfgWlp.enable || cfg.enable;
        message = "noctalia-shell: livePaper (waylivepaper) requires programs.noctalia-shell.enable = true.";
      }
    ];
  };
}
