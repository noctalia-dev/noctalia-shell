# Noctalia Configuration

The config file lives at `$XDG_CONFIG_HOME/noctalia/config.toml` (defaults to `~/.config/noctalia/config.toml`).

Changes are detected automatically via inotify — no restart required.

---

## Table of Contents

- [Bar](#bar)
- [Per-monitor overrides](#per-monitor-overrides)
- [Widget definitions](#widget-definitions)
- [Built-in widgets](#built-in-widgets)
- [Dock](#dock)
- [Weather](#weather)
- [Audio](#audio)
- [Night Light](#night-light)
- [Idle](#idle)
- [Shell](#shell)
- [Keybinds](#keybinds)
- [OSD](#osd)
- [Wallpaper](#wallpaper)
- [Overview](#overview)
- [Theme](#theme)
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
end    = ["tray", "notifications", "volume", "power_profiles", "battery", "wallpaper", "session", "clock"]
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

### `audio_visualizer`

Shows a simple horizontal audio spectrum using the current PipeWire monitor stream.

| Setting  | Type   | Default | Description                    |
|----------|--------|---------|--------------------------------|
| `width`  | number | `56`    | Widget width in screen pixels  |
| `height` | number | `16`    | Widget height in screen pixels |
| `bands`  | number | `16`    | Number of spectrum bands       |

```toml
[widget.audio-vis]
type = "audio_visualizer"
width = 64
height = 16
bands = 20
```

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

### `network`

Shows the current network connection (Wi-Fi SSID and signal strength, or wired) via NetworkManager. Dims and shows a `wifi-off` glyph when disconnected.

| Setting      | Type | Default | Description                                |
|--------------|------|---------|--------------------------------------------|
| `show_label` | bool | `true`  | Show the SSID or interface name next to the glyph |

```toml
[widget.network]
type = "network"
show_label = false
```

---

### `keyboard_layout`

Shows the current keyboard layout indicator from your active XKB state.

Left-click cycles layouts using the compositor backend when supported. You can still override that with `cycle_command` if you want a custom shell command instead.

| Setting         | Type   | Default   | Description                                                         |
|-----------------|--------|-----------|---------------------------------------------------------------------|
| `display`       | string | `"short"` | Show either the compact code (`short`) or full layout name (`full`) |
| `cycle_command` | string | `""`      | Optional override command run on left click instead of the compositor backend |

The widget always shows the keyboard glyph.

```toml
[widget.keyboard_layout]
display = "short" # short | full
```

Use the widget by name in your bar:

```toml
[bar.main]
end = ["keyboard_layout", "clock"]
```

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

### `wallpaper`

Shows a glyph and opens the wallpaper picker panel on click. No configurable settings.

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

IPC:

```sh
noctalia msg enable-idle-inhibitor
noctalia msg disable-idle-inhibitor
noctalia msg toggle-idle-inhibitor
```

---

### `nightlight`

Cycles through three night light states on click:

| State    | Icon       | Meaning                                              |
|----------|------------|------------------------------------------------------|
| Off      | moon-off   | Night light disabled                                 |
| On       | moon       | Scheduled — follows `start_time`/`stop_time` or location; dimmed during day phase, highlighted at night |
| Forced   | moon-stars | Always-on override — ignores schedule and location   |

No configurable settings.

IPC:

```sh
noctalia msg toggle-nightlight
noctalia msg toggle-force-nightlight
```

---

### `theme_mode`

Toggles the active theme mode between dark and light on click.

- Dark mode shows a moon glyph.
- Light mode shows a sun glyph.

No configurable settings.

IPC:

```sh
noctalia msg toggle-theme-mode
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

## Dock

A standalone application dock that displays pinned and running apps. Disabled by default — set `enabled = true` to activate it.

```toml
[dock]
enabled            = true
position           = "bottom"   # top | bottom | left | right
active_monitor_only = false      # when true, only show apps/windows from the active monitor in the dock

icon_size          = 48         # icon size in pixels
padding            = 8          # inner padding around the icon row (all sides)
item_spacing       = 6          # gap between items in pixels
background_opacity = 0.88       # dock panel background alpha (0.0–1.0)
radius             = 16         # dock panel corner radius in pixels
margin_h           = 0          # horizontal compositor margin (space from screen sides)
margin_v           = 8          # vertical gap between dock and screen edge

shadow_blur        = 12         # drop-shadow blur radius in pixels (0 = no shadow)
shadow_offset_x    = 0          # horizontal shadow offset
shadow_offset_y    = 4          # vertical shadow offset (positive = down)

show_running       = true       # also show running apps that are not in the pinned list
auto_hide          = false      # fade out when the pointer leaves; fade in on approach
active_scale       = 1.0        # icon scale for the focused app (clamped to 0.1-1.75)
inactive_scale     = 0.85       # icon scale for non-focused apps (clamped to 0.1-1.0)
active_opacity     = 1.0        # icon opacity for the focused app
inactive_opacity   = 0.85       # icon opacity for non-focused apps
show_instance_count = true      # show a badge with the window count when an app has 2+ open windows

# Pinned apps: desktop entry IDs, StartupWMClass, or human-readable names.
# Example: "firefox", "code", "org.gnome.Nautilus"
pinned = ["firefox", "code", "kitty"]
```

### `pinned` matching

Each entry in `pinned` is matched against desktop entries using these rules in order:

1. Desktop entry ID stem (e.g. `"firefox"` matches `firefox.desktop` and `org.mozilla.Firefox.desktop`)
2. `StartupWMClass` field of the desktop entry
3. App `Name` field (case-insensitive)
4. Full desktop entry path

If no match is found, a placeholder slot is reserved so the dock position is preserved.

### Active app emphasis

- The active app icon uses `active_scale` and `active_opacity`.
- Non-active app icons use `inactive_scale` and `inactive_opacity`.
- Focus changes animate smoothly between the active and inactive scale/opacity values.

### Auto-hide

When `auto_hide = true`, the dock:
- Does **not** reserve compositor exclusive zone (windows are not pushed aside).
- Fades out after the pointer leaves (uses a slow ease-in animation).
- Fades back in when the pointer enters the thin edge trigger strip, so you can reach it by moving the cursor to the screen edge even when the dock is invisible.

### IPC

```sh
noctalia msg show-dock       # Re-display all instances
noctalia msg hide-dock       # Close all instances until next reload
noctalia msg toggle-dock     # Toggle dock visibility
noctalia msg reload-dock     # Reload dock configuration
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
transition_duration = 1500      # milliseconds
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
use_weather_location = true   # use weather coordinates when no manual schedule or location is set

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
- `use_weather_location = false` disables weather coordinates as a location source; explicit `latitude`/`longitude` or `start_time`/`stop_time` must be provided.
- If only one of latitude/longitude is provided, Night Light refuses to start.

IPC force controls:

```sh
noctalia msg enable-nightlight
noctalia msg disable-nightlight
noctalia msg toggle-nightlight
noctalia msg toggle-force-nightlight
```

- `enable-nightlight` / `disable-nightlight` / `toggle-nightlight` control schedule enable state.
- `toggle-force-nightlight` toggles forced night mode.

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

When you use the `noctalia:` prefix, the rest of the string is executed through the same IPC command registry as `noctalia msg`.
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
clipboard_auto_paste = "auto" # off | auto | ctrl_v | ctrl_shift_v | shift_insert

[shell.animation]
enabled = true              # master switch for UI and theme motion
speed = 1.0                 # 1.0 = normal, 0.5 = 2x slower, 2.0 = 2x faster
```

`ui_scale` is completely separate from `bar.scale`:
- `bar.scale` only affects bar widget content
- `shell.ui_scale` is for control center, launcher, clipboard, and other non-bar shell UI
- neither setting changes Wayland output scale / HiDPI buffer scale

`notifications_dbus` only controls the external D-Bus notification daemon. When disabled, apps cannot send notifications through `org.freedesktop.Notifications`, but Noctalia internal notifications still appear in popups, history, and widgets.

`shell.animation.enabled` disables animated transitions globally. `shell.animation.speed` scales animation durations globally; values below `1.0` slow motion down and values above `1.0` speed it up.

`avatar_path` sets the avatar image shown in the Control Center Overview session card.

`clipboard_auto_paste` controls what Noctalia sends after selecting a clipboard entry. `auto` matches the old shell behavior: image entries use `Ctrl+V`, text entries use `Ctrl+Shift+V`. `ctrl_v` works for most GUI apps, `ctrl_shift_v` and `shift_insert` are better fits for many terminals, and `off` keeps the current behavior to “copy only, no automatic paste”.

---

## Keybinds

Centralized keyboard actions used by shell panels (`launcher`, `session`, `clipboard`, `wallpaper`, and panel close/cancel).

Supported actions:
- `validate`
- `cancel`
- `left`
- `right`
- `up`
- `down`

Each action accepts either:
- one string chord, or
- an array of string chords

Chord format:
- `key`
- `modifier+key`
- `modifier+modifier+key`

Supported modifiers:
- `ctrl`
- `shift`
- `alt`

`super/windows` bindings are intentionally rejected (`super`, `win`, `windows`, `logo`, `meta`, `mod4`) and produce a config parse error.

```toml
[keybinds]
validate = ["return", "kp_enter"]
cancel = ["escape"]
left = ["left", "ctrl+h"]
right = ["right", "ctrl+l"]
up = ["up", "ctrl+k"]
down = ["down", "ctrl+j"]
```

Defaults (when unset):
- `validate` = `return`, `kp_enter`
- `cancel` = `escape`
- `left` = `left`
- `right` = `right`
- `up` = `up`
- `down` = `down`

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

## Theme

Controls the colors used by the shell — bars, panels, widgets, OSD, overview, and notifications. Pick a bundled scheme or have Noctalia generate one from the current wallpaper.

```toml
[theme]
source           = "builtin"      # builtin | wallpaper
builtin          = "Noctalia"     # bundled scheme name
wallpaper_scheme = "m3-content"   # generator used when source = "wallpaper"
mode             = "dark"         # dark | light | auto

[theme.templates]
enable_builtins       = true
builtin_ids           = []        # built-in template ids to apply
enable_user_templates = false
user_config           = "~/.config/noctalia/user-templates.toml"
```

**`source`** selects where the palette comes from:

- `builtin` — use one of the schemes compiled into the binary (see list below).
- `wallpaper` — generate a palette from the current default wallpaper each time it changes.

**`builtin`** names which bundled scheme to load when `source = "builtin"`. Unknown names fall back to `Noctalia`. Available schemes:

`Ayu`, `Catppuccin`, `Dracula`, `Eldritch`, `Gruvbox`, `Kanagawa`, `Noctalia`, `Nord`, `Rosé Pine`, `Tokyo-Night`

**`wallpaper_scheme`** picks the generator used when `source = "wallpaper"`. The `m3-*` schemes are Material Design 3 palettes built on Google's Material Color Utilities; the rest are custom HSL-space generators with distinct aesthetics.

- `m3-tonal-spot` — M3 default, balanced tones anchored on the seed color
- `m3-content` — M3 for content-forward UIs, higher chroma
- `m3-fruit-salad` — M3 with playful cross-hue accents
- `m3-rainbow` — M3 spanning the wheel for multi-accent layouts
- `m3-monochrome` — M3 collapsed to a single hue
- `vibrant` — custom, saturated and high-contrast
- `faithful` — custom, stays close to the source image
- `dysfunctional` — custom, deliberately off-kilter
- `muted` — custom, low-saturation

**`mode`** selects the dark or light variant. `auto` is treated as `dark` until system light/dark tracking lands. Bundled schemes and wallpaper-derived palettes both provide dark and light variants.

Theme changes apply live when you edit `config.toml`, and wallpaper-derived themes re-resolve automatically when the default wallpaper changes.

### External App Templates

Noctalia can also apply generated colors to external app config templates whenever the resolved theme changes.

`[theme.templates]` controls that behavior:

- `enable_builtins` enables the shipped built-in template catalog.
- `builtin_ids` selects which built-in templates actually run. The default is an empty array, so nothing is applied until you opt in.
- `enable_user_templates` enables loading your own `user-templates.toml`.
- `user_config` points at that extra config file.

Example:

```toml
[theme.templates]
enable_builtins = true
builtin_ids = ["foot", "walker", "gtk3", "gtk4"]
enable_user_templates = true
user_config = "~/.config/noctalia/user-templates.toml"
```

Built-in template ids can be listed with:

```sh
noctalia theme --list-builtins
```

When `enable_user_templates = true`, Noctalia creates a stub `~/.config/noctalia/user-templates.toml` if it does not already exist.

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
