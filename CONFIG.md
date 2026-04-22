# Noctalia Configuration

Config file: `$XDG_CONFIG_HOME/noctalia/config.toml` (defaults to `~/.config/noctalia/config.toml`)

Changes are hot-reloaded via inotify — no restart required.

A ready-to-use starting config with all defaults is at [`example.toml`](example.toml).

Notification daemon toggle: use `[notification].enable_daemon` (documented in [`config/services.md`](config/services.md)).

---

## Reference

| Section | Description |
|---------|-------------|
| [Bar](config/bar.md) | Bar layout, per-monitor overrides, auto-hide, widget capsule styling |
| [Widgets](config/widgets.md) | Widget definitions and all built-in widget types |
| [Dock](config/dock.md) | Application dock — pinned apps, auto-hide, IPC |
| [Desktop Widgets](config/desktop-widgets.md) | Desktop overlay widgets — edit mode, state file format |
| [Wallpaper](config/wallpaper.md) | Wallpaper picker and overview backdrop |
| [Theme](config/theme.md) | Color schemes, modes, wallpaper-derived palettes, app templates |
| [Services](config/services.md) | Audio, Brightness, Night Light, Weather, Idle, Notifications |
| [Shell](config/shell.md) | Global UI settings, OSD, Keybinds, Hooks |
