# Noctalia Configuration

The config file lives at `$XDG_CONFIG_HOME/noctalia/config.toml` (defaults to `~/.config/noctalia/config.toml`).

Changes are detected automatically via inotify — no restart required.

---

## Table of Contents

- [Bar](#bar)
- [Per-monitor overrides](#per-monitor-overrides)
- [Widget definitions](#widget-definitions)
- [Built-in widgets](#built-in-widgets)
- [Weather](#weather)
- [Audio](#audio)
- [Night Light](#night-light)
- [Idle](#idle)
- [Shell](#shell)
- [OSD](#osd)
- [Wallpaper](#wallpaper)
- [Overview](#overview)
- [Full example](#full-example)

---

## Bar

Bars are defined as named subtables under `[bar.*]`. Each bar is spawned on every connected output, then per-monitor overrides are applied.

```toml
[bar.main]
position        = "top"       # top | bottom | left | right
enabled         = true

height          = 34          # bar thickness in pixels
background_opacity = 1.0      # bar background alpha, from 0.0 (transparent) to 1.0 (opaque)
radius          = 16          # global corner radius fallback
radius_top_left = 16
radius_top_right = 16
radius_bottom_left = 16
radius_bottom_right = 16
margin_h        = 180         # horizontal gap between bar and screen edge
margin_v        = 10          # vertical gap between bar and screen edge
padding_h       = 14          # padding from bar edge to the start/end widget sections
widget_spacing  = 6           # gap between widgets within a section
scale           = 1.0         # content scale multiplier for icons and text (default: 1.0)

shadow_blur     = 12          # blur radius in pixels (0 = no shadow)
shadow_offset_x = 3           # horizontal shadow offset (positive = right)
shadow_offset_y = 6           # vertical shadow offset (positive = down)


start  = ["cpu", "temp", "ram", "active_window"]  # widget names in the left/top section
center = ["workspaces"]       # widget names in the center section
end    = ["tray", "notifications", "volume", "power_profiles", "battery", "session", "clock"]
```

Radius precedence:
- `radius` is the global fallback.
- Per-corner values override `radius` when provided.

All fields are optional and fall back to the defaults shown above. Multiple `[bar.*]` entries are supported — each is independently configured and rendered on all outputs (subject to monitor overrides).

---

## Per-monitor overrides

Inside a bar you can add named monitor subtables under `[bar.<name>.monitor.*]`. **First match wins**, in file order.

```toml
[bar.main.monitor.dp1]
match          = "DP-1"    # connector name or description substring
enabled        = true
height         = 44
background_opacity = 0.9
radius         = 0
radius_top_left = 12
radius_top_right = 12
radius_bottom_left = 0
radius_bottom_right = 0
padding_h      = 20
widget_spacing = 6
start          = []
center         = ["workspaces"]
end            = ["volume", "clock"]
```

**`match` resolution** — compared against:
1. Exact connector name (`eDP-1`, `DP-1`, `HDMI-A-1`, …)
2. Any substring of the monitor's description string (`"LG"`, `"4K"`, `"DELL"`, …)

`match` defaults to the subtable key name when omitted, so `[bar.main.monitor."DP-1"]` without a `match` field works too.

Only the fields you specify are overridden; everything else falls through to the `[bar.*]` defaults. `scale` and `background_opacity` are also supported in monitor overrides.

---

## Widget definitions

Widget definitions are optional. When a name in a widget list matches a `[widget.<name>]` entry, that entry's `type` and settings are used. When there is no match, the name itself is treated as the widget type with default settings.

```toml
[widget.<name>]
type = "<widget-type>"   # defaults to <name> when omitted
# ...widget-specific settings
```

This allows multiple instances of the same widget type:

```toml
[widget.clock-seconds]
type   = "clock"
format = "{:%H:%M:%S}"

[bar.main]
end = ["clock", "clock-seconds"]   # two clock widgets, different formats
```

---

## Built-in widgets

### `clock`

Displays the current time.

| Setting  | Type   | Default    | Description                              |
|----------|--------|------------|------------------------------------------|
| `format` | string | `{:%H:%M}` | `std::format`-style chrono format string |

```toml
[widget.clock]
format = "{:%H:%M}"

[widget.clock-seconds]
type   = "clock"
format = "{:%H:%M:%S}"
```

---

### `spacer`

Empty space between widgets.

| Setting  | Type   | Default | Description                              |
|----------|--------|---------|------------------------------------------|
| `length` | number | `8`     | Spacer length in screen pixels           |

```toml
[widget.gap]
type   = "spacer"
length = 24
```

---

### `workspaces`

Workspace switcher with solid dots/pills and optional labels.

| Setting   | Type   | Default  | Description                                      |
|-----------|--------|----------|--------------------------------------------------|
| `display` | string | `"id"`   | Label mode: `"none"`, `"id"`, or `"name"`       |

```toml
[widget.workspaces]
type = "workspaces"
display = "id" # none | id | name
```

---

### `volume`

Shows the default audio sink volume and mute state via PipeWire. No configurable settings.

---

### `media`

Shows the current media artwork and track title from MPRIS.

| Setting      | Type   | Default | Description                         |
|--------------|--------|---------|-------------------------------------|
| `max_length` | number | `220`   | Maximum length for the title text   |
| `art_size`   | number | `24`    | Artwork size in pixels before scale |

```toml
[widget.media]
type = "media"
max_length = 220
art_size = 24
```

---

### `battery`

Shows battery charge level and state via UPower. Hides itself automatically when no battery is present (safe to include on desktops).

No configurable settings.

---

### `weather`

Shows the current weather in the bar and opens the Weather control-center tab on click.

| Setting          | Type   | Default | Description                                            |
|------------------|--------|---------|--------------------------------------------------------|
| `max_length`     | number | `160`   | Maximum length for the weather text                    |
| `show_condition` | bool   | `true`  | Show condition text like `Overcast` next to temperature |

```toml
[widget.weather]
type = "weather"
max_length = 180
show_condition = false
```

---

### `notifications`

Shows the pending notification count. No configurable settings.

---

### `session`

Shows a power glyph and opens the session menu panel on click. No configurable settings.

---

### `tray`

System tray (StatusNotifierItem). No configurable settings.

---

### `power_profiles`

Shows the current power profile using a glyph and cycles to the next available profile on click.

No configurable settings.

---

### `idle_inhibitor`

Shows a keep-awake glyph and toggles the compositor idle inhibitor on click.

This uses the standard Wayland `zwp_idle_inhibit_manager_v1` protocol when available.

No configurable settings.

You can also control it over Noctalia IPC:

```sh
noctalia-ipc enable-idle-inhibitor
noctalia-ipc disable-idle-inhibitor
noctalia-ipc toggle-idle-inhibitor
```

---

### `sysmon`

System resource monitor. Shows an icon and value for one configurable stat. Multiple instances with different stats can coexist on the same bar.

| Setting   | Type   | Default       | Description                                                                   |
|-----------|--------|---------------|-------------------------------------------------------------------------------|
| `stat`    | string | `"cpu_usage"` | Which stat to display (see table below)                                       |
| `path`    | string | `"/"`         | Mount path for `disk_pct` (ignored otherwise)                                 |
| `display` | string | `"gauge"`     | `"gauge"` = icon + vertical fill bar; `"graph"` = icon + sparkline (1-min history) + value; `"text"` = icon + value |

**`stat` values:**

| Value       | Display  | Description                 |
|-------------|----------|-----------------------------|
| `cpu_usage` | `75%`    | CPU utilisation (all cores) |
| `cpu_temp`  | `65°C`   | CPU package temperature     |
| `ram_used`  | `4.2G`   | RAM used (human-readable)   |
| `ram_pct`   | `26%`    | RAM used %                  |
| `swap_pct`  | `12%`    | Swap used %                 |
| `disk_pct`  | `45%`    | Disk used % for `path`      |

```toml
[widget.cpu]
type = "sysmon"
stat = "cpu_usage"

[widget.temp]
type = "sysmon"
stat = "cpu_temp"

[widget.ram]
type = "sysmon"
stat = "ram_used"

[widget.disk]
type = "sysmon"
stat = "disk_pct"
path = "/"
```

---

## Wallpaper

```toml
[wallpaper]
enabled             = true
fill_mode           = "crop"    # center | crop | fit | stretch | repeat
transition          = ["fade", "wipe", "disc", "stripes", "zoom", "honeycomb"]
                                # array of effects to pick from at random each transition
                                # omit to use all effects; valid values: fade | wipe | disc | stripes | zoom | honeycomb
transition_duration = 1500.0    # milliseconds
edge_smoothness     = 0.3       # 0.0 – 1.0

# Directory browsed by the wallpaper picker panel.
directory           = "/home/user/Wallpapers"
# Optional separate directories used when light/dark mode switching lands.
# Both are parsed today but not yet consumed by the renderer.
directory_light     = "/home/user/Wallpapers/Light"
directory_dark      = "/home/user/Wallpapers/Dark"

# Per-monitor overrides — same match rules as bar monitor overrides
[wallpaper.monitor.DP-2]
enabled         = false
# Each monitor override may point at its own directories. When unset, the
# top-level [wallpaper] directories are used.
directory       = "/home/user/Wallpapers/Vertical"
directory_light = "/home/user/Wallpapers/Vertical/Light"
directory_dark  = "/home/user/Wallpapers/Vertical/Dark"
```

The wallpaper picker panel (toggle via IPC `wallpaper`) lists the images found in
`directory` as a grid of thumbnails. Selecting a monitor in the panel's toolbar
switches to that monitor's override directory (falling back to the base
`directory`). Clicking a tile writes the chosen path to `state.toml` and applies
it immediately; picking a wallpaper while **ALL** is selected applies it to
every connected output.

---

## Overview

Renders a blurred and tinted copy of the current wallpaper as a layer-shell backdrop for compositor overview modes (e.g. niri's overview). Disabled by default.

To make the surface visible during niri overview, add a layer-rule in your niri config:

```kdl
layer-rule {
    match namespace="^noctalia-overview"
    place-within-backdrop true
}
```

```toml
[overview]
enabled          = false
blur_intensity   = 0.5   # 0.0 = no blur, 1.0 = maximum blur
tint_intensity   = 0.3   # 0.0 = no tint, 1.0 = fully opaque tint
```

The tint color is `palette.surface` and cannot currently be configured.

---

## OSD

```toml
[osd]
position = "top_right"   # top_right | top_left | top_center | bottom_right | bottom_left | bottom_center
```

The OSD currently powers the volume HUD and defaults to `top_right`.

---

## Audio

```toml
[audio]
enable_overdrive = false   # allow the audio volume sliders to go above 100%
```

When `enable_overdrive` is `false`, the Control Center output and microphone sliders clamp to `100%`.
When it is `true`, those sliders allow values up to `150%`.

---

## Night Light

Uses `wlsunset` to apply temperature shifts.

```toml
[nightlight]
enabled = false
force = false                 # force night mode from startup
auto_detect = true            # use weather coordinates when no manual schedule is set

temperature_day = 6500        # Kelvin, day color temperature
temperature_night = 4000      # Kelvin, night color temperature

# Option A: explicit schedule
start_time = "20:30"          # HH:MM (sunset / night starts)
stop_time = "07:30"           # HH:MM (sunrise / day starts)

# Option B: geolocation schedule (used when start/stop are missing)
# latitude = 52.5200
# longitude = 13.4050
```

Notes:
- `start_time` + `stop_time` always take priority.
- If manual times are missing, explicit `latitude` + `longitude` are used.
- If manual times and explicit coordinates are both missing, Night Light uses WeatherService coordinates.
- `auto_detect = false` disables weather as the primary mode, but weather is still used as a final fallback when no other schedule is configured.
- If only one of latitude/longitude is provided, Night Light refuses to start.

IPC force controls:

```sh
noctalia-ipc enable-nightlight
noctalia-ipc disable-nightlight
noctalia-ipc toggle-nightlight
noctalia-ipc force-nightlight
```

- `enable-nightlight` / `disable-nightlight` / `toggle-nightlight` control schedule enable state.
- `force-nightlight` toggles forced night mode.

---

## Idle

Idle behavior is defined as named entries under `[idle.behavior.*]`.

When no `config.toml` exists, Noctalia uses this built-in default:

```toml
[idle.behavior.lock]
timeout = 660
command = "noctalia:lock"
enabled = false
```

```toml
[idle.behavior.lock]
timeout = 16
command = "noctalia:lock"

[idle.behavior.screen-off]
timeout = 32
command = "noctalia:dpms-off"

[idle.behavior.custom]
timeout = 48
command = "noctalia-msg lock"
```

Available fields:

| Setting         | Type   | Default | Description |
|----------------|--------|---------|-------------|
| `enabled`      | bool   | `true`  | Enable or disable this behavior entry |
| `timeout`      | int    | `0`     | Timeout in seconds before the behavior triggers |
| `command`      | string | `""`    | Command to execute when the idle timeout is reached |

`command` can be either:

- a regular shell command such as `notify-send 'Idle' 'Locking soon'`
- a Noctalia IPC command using the `noctalia:` prefix

When you use the `noctalia:` prefix, the rest of the string is executed through the same IPC command registry as `noctalia-ipc`.
That means all existing Noctalia IPC commands are available inside idle behaviors, not just a special idle-only subset.

Examples:

- `noctalia:lock`
- `noctalia:dpms-off`
- `noctalia:dpms-on`
- `noctalia:enable-idle-inhibitor`
- `noctalia:disable-idle-inhibitor`
- `noctalia:toggle-idle-inhibitor`
- `noctalia:toggle-panel launcher`
- `noctalia:toggle-panel session-menu`
- `noctalia:toggle-panel clipboard`

Idle behavior uses the Wayland `ext_idle_notifier_v1` protocol, so it reacts to compositor idle notifications instead of polling. The standard idle notification path respects active idle inhibitors.

Examples:

```toml
[idle.behavior.notify]
timeout = 300
command = "notify-send 'Noctalia' 'You have been idle for 5 minutes'"

[idle.behavior.lock]
timeout = 660
command = "noctalia:lock"
enabled = false
```

---

## Shell

Shell-wide UI settings for non-bar surfaces.

```toml
[shell]
ui_scale = 1.0              # content scale multiplier for panels and other non-bar shell UI
lang = "en"                 # overidde language detection
notifications_dbus = true   # when false, don't claim org.freedesktop.Notifications
avatar_path = "/home/you/Pictures/avatar.png" # avatar image for Control Center overview session card
```

`ui_scale` is completely separate from `bar.scale`:
- `bar.scale` only affects bar widget content
- `shell.ui_scale` is for control center, launcher, clipboard, and other non-bar shell UI
- neither setting changes Wayland output scale / HiDPI buffer scale

`notifications_dbus` only controls the external D-Bus notification daemon. When disabled, apps cannot send notifications through `org.freedesktop.Notifications`, but Noctalia internal notifications still appear in popups, history, and widgets.

`avatar_path` sets the avatar image shown in the Control Center Overview session card.

---

## Weather

```toml
[weather]
enabled         = true
auto_locate     = false        # when true, resolve coordinates from your IP address
address         = "Toronto, ON" # used when auto_locate = false
refresh_minutes = 30
unit            = "celsius"   # celsius | fahrenheit
```

`auto_locate` is off by default. When it is disabled, Noctalia geocodes `address` to latitude/longitude and then fetches current weather plus a 6-day forecast. When `auto_locate` is enabled, the configured address is ignored and the shell resolves your location via IP before fetching the forecast.

The bar widget type is `weather`, and the control center gains a `Weather` tab automatically.

---

## Full example

```toml
# ─── Widget definitions ────────────────────────────────────────────────────────

[widget.clock]
format = "{:%H:%M}"

[widget.clock-seconds]
type   = "clock"
format = "{:%H:%M:%S}"

[widget.gap]
type  = "spacer"
width = 16

# ─── Bar ───────────────────────────────────────────────────────────────────────

[bar.main]
position        = "top"
height          = 40
background_opacity = 0.94
margin_h        = 12
margin_v        = 6
padding_h       = 16
widget_spacing  = 8
shadow_blur     = 16
shadow_offset_x = 6
shadow_offset_y = 6

start  = []
center = ["workspaces"]
end    = ["tray", "notifications", "volume", "battery", "clock"]

[bar.main.monitor.dp1]
match  = "DP-1"        # main 4K display — taller bar, show seconds
height = 44
background_opacity = 1.0
end    = ["tray", "notifications", "volume", "battery", "clock-seconds"]

[osd]
position = "top_right"

[audio]
enable_overdrive = false

[bar.main.monitor.hdmi]
match    = "HDMI-A-1"  # secondary 1080p — smaller, minimal widgets
height   = 36
background_opacity = 0.88
margin_h = 8
end      = ["volume", "clock"]

# ─── Overview ──────────────────────────────────────────────────────────────────

[overview]
enabled        = true
blur_intensity = 0.6
tint_intensity = 0.35

```
