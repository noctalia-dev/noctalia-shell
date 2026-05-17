{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.programs.noctalia;
  cfgLp = cfg.wallpaper.live_paper;
  # Best-effort read of the runtime live_paper toggle so presets staging can
  # default to "on whenever the visualizer is on". cfg.settings is freeform
  # (attrset | string | path); only an attrset is introspectable.
  livePaperEnabledInSettings =
    lib.isAttrs cfg.settings && (lib.attrByPath [ "wallpaper" "live_paper" "enabled" ] false cfg.settings);
  jsonFormat = pkgs.formats.json { };
  tomlFormat = pkgs.formats.toml { };

  generateConfig =
    format: name: value:
    if lib.isString value then
      pkgs.writeText name value
    else if builtins.isPath value || lib.isStorePath value then
      value
    else
      format.generate name value;

  generateToml = generateConfig tomlFormat;
  generateJson = generateConfig jsonFormat;
in
{
  options.programs.noctalia = {
    enable = lib.mkEnableOption "Whether to enable noctalia, a lightweight Wayland shell and bar.";

    systemd.enable = lib.mkEnableOption "Enables a systemd user service for noctalia.";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      description = "The noctalia package to use.";
    };

    settings = lib.mkOption {
      type =
        with lib.types;
        oneOf [
          tomlFormat.type
          str
          path
        ];
      default = { };
      description = ''
        Default settings for noctalia, Can be written as:
          - A Nix attrset (converted to TOML via nixpkgs' tomlFormat)
          - A raw TOML string
          - A path to a `.toml` file

        See <https://docs.noctalia.dev/v5> for more information and examples.

        Note: these settings can still be overwritten at runtime via the settings menu.
      '';
      example = lib.literalExpression ''
        shell = {
          font = "JetBrainsMono Nerd Font";
          settings_show_advanced = true;
        };

        theme = {
          mode = "dark";
          source = "builtin";
          builtin = "Catppuccin";
        };
      '';
    };

    customPalettes = lib.mkOption {
      type =
        with lib.types;
        oneOf [
          jsonFormat.type
          str
          path
        ];
      default = { };
      description = ''
        Custom color pallete options.

        See <https://docs.noctalia.dev/v5/theming/#custom_palette>.
      '';
    };

    # projectM/Milkdrop visualizer wallpaper. Runtime behaviour (enabled,
    # interval, fps, darken, audio source, …) lives in the freeform
    # `settings.wallpaper.live_paper` TOML table; the options here only
    # govern staging the presets pack on disk under
    # `$XDG_DATA_HOME/waylivepaper/presets` so the shell can find it.
    wallpaper.live_paper = {
      defaultPresets = lib.mkOption {
        type = lib.types.bool;
        default = livePaperEnabledInSettings;
        defaultText = lib.literalExpression ''
          settings.wallpaper.live_paper.enabled or false
        '';
        description = ''
          Symlink the bundled, brightness/strobe-filtered Milkdrop
          presets pack into `$XDG_DATA_HOME/waylivepaper/presets` so the
          live-paper visualizer has presets with no extra setup. Defaults
          to `true` whenever `settings.wallpaper.live_paper.enabled` is
          set, so enabling the visualizer is a single switch. Set to
          `false` to manage presets yourself (e.g. via
          `settings.wallpaper.live_paper.presets_dir`).
        '';
      };

      presetsSource = lib.mkOption {
        type = lib.types.path;
        description = ''
          Directory of `.milk` / `.prjm` presets symlinked into
          `$XDG_DATA_HOME/waylivepaper/presets` when `defaultPresets` is
          enabled. Defaults to the `presets-cream-of-the-crop` pack
          bundled with this flake, filtered for excessive brightness /
          strobing.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.noctalia = lib.mkIf cfg.systemd.enable {
      Unit = {
        Description = "Noctalia - A lightweight Wayland shell and bar";
        Documentation = "https://docs.noctalia.dev/v5/";
        PartOf = [ config.wayland.systemd.target ];
        After = [ config.wayland.systemd.target ];
        X-Restart-Triggers =
          lib.optional (cfg.settings != { }) "${config.xdg.configFile."noctalia/config.toml".source}"
          ++ lib.mapAttrsToList (
            name: _: "${config.xdg.configFile."noctalia/palettes/${name}.json".source}"
          ) cfg.customPalettes;
      };

      Service = {
        ExecStart = lib.getExe cfg.package;
        Restart = "on-failure";
      };

      Install.WantedBy = [ config.wayland.systemd.target ];
    };

    home.packages = lib.optional (cfg.package != null) cfg.package;

    xdg = {
      configFile = lib.mkMerge [
        (lib.mkIf (cfg.settings != { }) {
          "noctalia/config.toml".source = generateToml "config.toml" cfg.settings;
        })
        (lib.mapAttrs' (
          name: palette:
          lib.nameValuePair "noctalia/palettes/${name}.json" {
            source = generateJson "${name}-palette.json" palette;
          }
        ) cfg.customPalettes)
      ];

      # Stage the presets pack so the visualizer renderer discovers it at
      # the well-known XDG location without any extra configuration.
      dataFile."waylivepaper/presets" = lib.mkIf cfgLp.defaultPresets {
        source = cfgLp.presetsSource;
      };
    };

    assertions = [
      {
        assertion = !cfg.systemd.enable || cfg.package != null;
        message = "programs.noctalia.package cannot be null when programs.noctalia.systemd.enable is true";
      }
    ];
  };
}
