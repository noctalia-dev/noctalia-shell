# Desktop Widgets

Desktop widgets are enabled from `config.toml`. Widget instances and edit-mode grid settings are stored in a separate state file.

- Config toggle: `[desktop_widgets]` in `~/.config/noctalia/config.toml`
- State file: `$XDG_STATE_HOME/noctalia/desktop_widgets.toml` (falls back to `~/.local/state/noctalia/desktop_widgets.toml`)

```toml
[desktop_widgets]
enabled = true
```

When enabled, Noctalia renders each desktop widget as its own tightly-sized layer-shell surface on the `Bottom` layer. The current implementation ships `clock`, `audio_visualizer`, `sticker`, and `weather` widget types plus an interactive edit mode.

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

The `weather` widget draws the current weather glyph alongside the temperature and short condition, driven by the shared `WeatherService`. It requires `[weather] enabled = true` in `config.toml` (see [services.md](services.md#weather)) — the widget will render a placeholder otherwise.

```toml
[[widget]]
id       = "desktop-widget-0000000000000003"
type     = "weather"
output   = "DP-1"
cx       = 320.0
cy       = 200.0
scale    = 1.0
rotation = 0.0
```
