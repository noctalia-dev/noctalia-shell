# Noctalia Configuration

The config file lives at `$XDG_CONFIG_HOME/noctalia/config.toml` (defaults to `~/.config/noctalia/config.toml`).

Changes are detected automatically via inotify — no restart required.

---

## Table of Contents

- [Bar](#bar)
- [Per-monitor overrides](#per-monitor-overrides)
- [Widget definitions](#widget-definitions)
- [Built-in widgets](#built-in-widgets)
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
margin_h        = 180         # horizontal gap between bar and screen edge
margin_v        = 10          # vertical gap between bar and screen edge
padding_h       = 14          # padding from bar edge to the start/end widget sections
widget_spacing  = 6           # gap between widgets within a section
scale           = 1.0         # content scale multiplier for icons and text (default: 1.0)

shadow_blur     = 12          # blur radius in pixels (0 = no shadow)
shadow_offset_x = 0           # horizontal shadow offset (positive = right)
shadow_offset_y = 6           # vertical shadow offset (positive = down)


start  = ["sysmon"]           # widget names in the left/top section
center = ["workspaces"]       # widget names in the center section
end    = ["tray", "notifications", "volume", "battery", "spacer", "clock"]
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

### `battery`

Shows battery charge level and state via UPower. Hides itself automatically when no battery is present (safe to include on desktops).

No configurable settings.

---

### `notifications`

Shows the pending notification count. No configurable settings.

---

### `tray`

System tray (StatusNotifierItem). No configurable settings.

---

### `sysmon`

System resource monitor. Shows an icon and value for one configurable stat. Multiple instances with different stats can coexist on the same bar.

| Setting | Type   | Default       | Description                                   |
|---------|--------|---------------|-----------------------------------------------|
| `stat`  | string | `"cpu_usage"` | Which stat to display (see table below)       |
| `path`  | string | `"/"`         | Mount path for `disk_pct` (ignored otherwise) |

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
transition          = "fade"    # fade | wipe | disc | stripes | pixelate | honeycomb
transition_duration = 1500.0    # milliseconds
edge_smoothness     = 0.5       # 0.0 – 1.0
```

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

[bar.main.monitor.hdmi]
match    = "HDMI-A-1"  # secondary 1080p — smaller, minimal widgets
height   = 34
margin_h = 8
end      = ["volume", "clock"]

# ─── Wallpaper ─────────────────────────────────────────────────────────────────

[wallpaper]
enabled             = true
fill_mode           = "crop"
transition          = "fade"
transition_duration = 1500.0
edge_smoothness     = 0.5
```
