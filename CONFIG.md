# Configuration

Noctalia has two configuration layers:

- Declarative user config lives in `$XDG_CONFIG_HOME/noctalia/` or `~/.config/noctalia/`.
  Noctalia reads every `*.toml` file in that directory, sorted alphabetically, and deep-merges them into one config.
  A single `config.toml` is the simplest setup, but splitting config into files such as `bar.toml`, `theme.toml`,
  or `widgets.toml` is also supported.
- GUI-managed overrides live in `$XDG_STATE_HOME/noctalia/settings.toml` or
  `~/.local/state/noctalia/settings.toml`. This file is written by Noctalia itself for settings changed through the
  UI, IPC-backed controls, setup flows, and other runtime actions that need persistence.

Load order is built-in defaults first, then declarative config files, then `settings.toml`.
Because the state file is applied last, GUI overrides win over matching values in `config.toml`.

Use the declarative config directory for hand-authored, dotfile-managed configuration. Treat `settings.toml` as an
app-managed override layer: inspect or delete it when you want to understand or clear GUI changes, but do not rely on
it as the primary place for curated config. Keeping the override file outside `~/.config` also allows the GUI to save
changes when the config directory is read-only, such as on NixOS.

Both layers are watched for changes and hot-reloaded. If neither declarative config nor state overrides exist,
Noctalia falls back to built-in defaults in code.

A ready-to-use starting config with all defaults is at [example.toml](example.toml).

## Reference

| Section | Description |
|---------|-------------|
| [Bar](config/bar.md) | Bar layout, per-monitor overrides, auto-hide, widget capsule styling |
| [Widgets](config/widgets.md) | Widget definitions and all built-in widget types |
| [Scripted Widgets](config/scripted-widgets.md) | Custom Luau-driven bar widgets |
| [Dock](config/dock.md) | Application dock, pinned apps, auto-hide, IPC |
| [Desktop Widgets](config/desktop-widgets.md) | Desktop overlay widgets, edit mode, state file format |
| [Wallpaper](config/wallpaper.md) | Wallpaper picker, backdrop, automation |
| [Theme](config/theme.md) | Color schemes, modes, wallpaper-derived palettes |
| [Theming Templates](config/theming-templates.md) | App theme template generation and export paths |
| [Control Center](config/control-center.md) | Shortcut buttons on the overview tab |
| [Services](config/services.md) | Audio, sound cues, brightness, system monitor, night light, weather, idle, notifications |
| [Shell](config/shell.md) | Global UI settings, OSD, keybinds, hooks |
