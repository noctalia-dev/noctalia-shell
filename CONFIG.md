# Noctalia Configuration

Config file: `$XDG_CONFIG_HOME/noctalia/config.toml` (defaults to `~/.config/noctalia/config.toml`)

Changes are hot-reloaded via inotify — no restart required.

A ready-to-use starting config with all defaults is at [`example.toml`](example.toml).

Notification daemon toggle: use `[notification].enable_daemon` (documented in [`config/services.md`](config/services.md)).
Weather location visibility toggle: use `[shell].show_location` (documented in [`config/shell.md`](config/shell.md)).
Wallpaper automation: use `[wallpaper.automation]` (documented in [`config/wallpaper.md`](config/wallpaper.md)).
Wallpaper single-color fallback/fill: use `[wallpaper].fill_color` (documented in [`config/wallpaper.md`](config/wallpaper.md)).
Bar creation order: use `[bar].order` (documented in [`config/bar.md`](config/bar.md)).

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
| [Services](config/services.md) | Audio, Sound cues, Brightness, Night Light, Weather, Idle, Notifications |
| [Shell](config/shell.md) | Global UI settings, OSD, Keybinds, Hooks |
