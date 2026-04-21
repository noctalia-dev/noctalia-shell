# Desktop Widgets

Desktop widgets are enabled from `config.toml`. Widget instances and edit-mode grid settings are stored in a separate state file.

- Config toggle: `[desktop_widgets]` in `~/.config/noctalia/config.toml`
- State file: `$XDG_STATE_HOME/noctalia/desktop_widgets.toml` (falls back to `~/.local/state/noctalia/desktop_widgets.toml`)

```toml
[desktop_widgets]
enabled = true
```

When enabled, Noctalia renders each desktop widget as its own tightly-sized layer-shell surface on the `Bottom` layer. The current implementation ships `clock`, `audio_visualizer`, `sticker`, `weather`, and `media_player` widget types plus an interactive edit mode.

---

## Edit mode

### IPC

```sh
noctalia msg desktop-widgets-edit
noctalia msg desktop-widgets-exit
noctalia msg desktop-widgets-toggle-edit
```

### Controls

| Action | Effect |
|--------|--------|
| Drag widget body | Move |
| Drag outer selection ring | Rotate |
| Drag bottom-right handle | Scale uniformly |
| Drag toolbar handle | Reposition the editor toolbar on that output |
| `G` | Toggle snap grid |
| `Shift` + drag | Temporarily disable snapping |
| `Delete` / `Backspace` | Remove selected widget |
| `Escape` / click `Done` | Exit edit mode |

---

## State file format

Widget definitions are not read from `config.toml` — edit mode writes them to the state file so positions and transforms can be changed interactively.

```toml
schema_version = 1

[grid]
visible        = true
cell_size      = 16
major_interval = 4

[[widget]]
id       = "desktop-widget-0000000000000001"
type     = "clock"
output   = "DP-1"
cx       = 960.0
cy       = 540.0
scale    = 1.5
rotation = 0.0

[widget.settings]
format = "{:%H:%M}"
```

### Common settings

The `clock`, `weather`, and `media_player` widget types support two shared settings:

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `color` | string | `"on_surface"` | Text/glyph color — any palette role name (e.g. `"primary"`, `"tertiary"`) or a `"#rrggbb"` hex value |
| `shadow` | bool | `true` | Draw a drop shadow behind text and glyphs for readability on wallpapers |

```toml
[widget.settings]
color  = "primary"
shadow = true
```

---

### clock

```toml
[[widget]]
id       = "desktop-widget-0000000000000001"
type     = "clock"
output   = "DP-1"
cx       = 960.0
cy       = 540.0
scale    = 1.5
rotation = 0.0

[widget.settings]
format = "{:%H:%M}"
color  = "on_surface"
shadow = true
```

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `format` | string | `"{:%H:%M}"` | `std::chrono` format string |

---

### audio_visualizer

Desktop audio visualizers store an `aspect_ratio` setting for shape while `scale` controls overall size. They also accept optional `mirrored`, `low_color`, and `high_color` settings; both colors default to `primary`.

```toml
[[widget]]
id       = "desktop-widget-0000000000000002"
type     = "audio_visualizer"
output   = "DP-1"
cx       = 1040.0
cy       = 620.0
scale    = 1.25
rotation = 0.0

[widget.settings]
bands        = 32
aspect_ratio = 2.5
mirrored     = true
low_color    = "primary"
high_color   = "secondary"
```

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `bands` | int | `32` | Number of frequency bands |
| `aspect_ratio` | float | `2.5` | Width-to-height ratio |
| `mirrored` | bool | `true` | Mirror the spectrum horizontally |
| `low_color` | string | `"primary"` | Gradient low end — palette role or `"#rrggbb"` |
| `high_color` | string | `"primary"` | Gradient high end — palette role or `"#rrggbb"` |

---

### weather

Draws the current weather glyph alongside the temperature and short condition, driven by the shared `WeatherService`. Requires `[weather] enabled = true` in `config.toml` (see [services.md](services.md#weather)) — the widget will render a placeholder otherwise.

```toml
[[widget]]
id       = "desktop-widget-0000000000000003"
type     = "weather"
output   = "DP-1"
cx       = 320.0
cy       = 200.0
scale    = 1.0
rotation = 0.0

[widget.settings]
color  = "on_surface"
shadow = true
```

---

### media_player

MPRIS media player showing album art, track title, artist, and playback controls (prev, play/pause, next). Requires an active MPRIS player.

```toml
[[widget]]
id       = "desktop-widget-0000000000000004"
type     = "media_player"
output   = "DP-1"
cx       = 500.0
cy       = 700.0
scale    = 1.5
rotation = 0.0

[widget.settings]
layout = "horizontal"
color  = "on_surface"
shadow = true
```

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `layout` | string | `"horizontal"` | `"horizontal"` (cover on left) or `"vertical"` (cover on top) |

---

### sticker

Displays a static image file on the desktop.

```toml
[[widget]]
id       = "desktop-widget-0000000000000005"
type     = "sticker"
output   = "DP-1"
cx       = 800.0
cy       = 400.0
scale    = 1.0
rotation = 0.0

[widget.settings]
image_path = "/path/to/image.png"
```

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `image_path` | string | — | Absolute path to the image file |
