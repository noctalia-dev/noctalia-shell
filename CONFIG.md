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
- [Shell](#shell)
- [OSD](#osd)
- [Wallpaper](#wallpaper)
- [Full example](#full-example)

---

## Bar

Bars are defined as named subtables under `[bar.*]`. Each bar is spawned on every connected output, then per-monitor overrides are applied.

```toml
[bar.main]
position        = "top"       # top | bottom | left | right
enabled         = true

height          = 34          # bar thickness in pixels
radius          = 16          # corner radius in pixels (0 = square corners)
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
end    = ["tray", "notifications", "volume", "battery", "clock"]
```

All fields are optional and fall back to the defaults shown above. Multiple `[bar.*]` entries are supported — each is independently configured and rendered on all outputs (subject to monitor overrides).

---

## Per-monitor overrides

Inside a bar you can add named monitor subtables under `[bar.<name>.monitor.*]`. **First match wins**, in file order.

```toml
[bar.main.monitor.dp1]
match          = "DP-1"    # connector name or description substring
enabled        = true
height         = 44
radius         = 0
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

Only the fields you specify are overridden; everything else falls through to the `[bar.*]` defaults. `scale` is also supported in monitor overrides.

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

| Setting | Type   | Default | Description     |
|---------|--------|---------|-----------------|
| `width` | number | `8`     | Width in pixels |

```toml
[widget.gap]
type  = "spacer"
width = 24
```

---

### `workspaces`

Workspace switcher dots. No configurable settings.

---

### `volume`

Shows the default audio sink volume and mute state via PipeWire. No configurable settings.

---

### `media`

Shows the current media artwork and track title from MPRIS.

| Setting     | Type   | Default | Description                         |
|-------------|--------|---------|-------------------------------------|
| `max_width` | number | `220`   | Maximum width for the title text    |
| `art_size`  | number | `24`    | Artwork size in pixels before scale |

```toml
[widget.media]
type = "media"
max_width = 220
art_size = 24
```

---

### `battery`

Shows battery charge level and state via UPower. Hides itself automatically when no battery is present (safe to include on desktops).

No configurable settings.

---

### `weather`

Shows the current weather in the bar and opens the Weather control-center tab on click.

| Setting     | Type   | Default | Description                         |
|-------------|--------|---------|-------------------------------------|
| `max_width` | number | `160`   | Maximum width for the weather text  |

```toml
[widget.weather]
type = "weather"
max_width = 180
```

---

### `notifications`

Shows the pending notification count. No configurable settings.

---

### `tray`

System tray (StatusNotifierItem). No configurable settings.

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

# Per-monitor overrides — same match rules as bar monitor overrides
[wallpaper.monitor.DP-2]
enabled = false
```

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

## Shell

Shell-wide UI settings for non-bar surfaces.

```toml
[shell]
ui_scale = 1.0   # content scale multiplier for panels and other non-bar shell UI
```

`ui_scale` is completely separate from `bar.scale`:
- `bar.scale` only affects bar widget content
- `shell.ui_scale` is for control center, launcher, clipboard, and other non-bar shell UI
- neither setting changes Wayland output scale / HiDPI buffer scale

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
end    = ["tray", "notifications", "volume", "battery", "clock-seconds"]

[osd]
position = "top_right"

[audio]
enable_overdrive = false

[bar.main.monitor.hdmi]
match    = "HDMI-A-1"  # secondary 1080p — smaller, minimal widgets
height   = 36
margin_h = 8
end      = ["volume", "clock"]

# ─── Wallpaper ─────────────────────────────────────────────────────────────────

[wallpaper]
enabled             = true
fill_mode           = "crop"
transition          = ["fade", "wipe", "zoom", "disc", "honeycomb", "stripes"]
transition_duration = 1500.0
edge_smoothness     = 0.5
```
