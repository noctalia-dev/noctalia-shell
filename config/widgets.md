# Widgets

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

## `clock`

Displays the current time.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `format` | string | `{:%H:%M}` | `std::format`-style chrono format string (horizontal bars and vertical fallback) |
| `vertical_format` | string | `""` | Format used when the bar is vertical. When empty, falls back to `format` with `:` replaced by line breaks. |

```toml
[widget.clock]
format = "{:%H:%M}"
vertical_format = "{:%H\n%M}"

[widget.clock-seconds]
type   = "clock"
format = "{:%H:%M:%S}"
vertical_format = "{:%H\n%M\n%S}"
```

---

## `spacer`

Empty space between widgets.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `length` | number | `8` | Spacer length in screen pixels |

```toml
[widget.gap]
type   = "spacer"
length = 24
```

---

## `workspaces`

Workspace switcher with solid dots/pills and optional labels.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `display` | string | `"id"` | Label mode: `"none"`, `"id"`, or `"name"` |

```toml
[widget.workspaces]
display = "id"   # none | id | name
```

---

## `sysmon`

System resource monitor. Shows an icon and value for one configurable stat. Multiple instances with different stats can coexist on the same bar.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `stat` | string | `"cpu_usage"` | Which stat to display (see table below) |
| `path` | string | `"/"` | Mount path for `disk_pct` (ignored otherwise) |
| `display` | string | `"gauge"` | `"gauge"` = icon + vertical fill bar; `"graph"` = icon + sparkline + value; `"text"` = icon + value |

**`stat` values:**

| Value | Display | Description |
|-------|---------|-------------|
| `cpu_usage` | `75%` | CPU utilisation (all cores) |
| `cpu_temp` | `65°C` | CPU package temperature |
| `ram_used` | `4.2G` | RAM used (human-readable) |
| `ram_pct` | `26%` | RAM used % |
| `swap_pct` | `12%` | Swap used % |
| `disk_pct` | `45%` | Disk used % for `path` |

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

## `volume`

Shows the default audio sink volume and mute state via PipeWire. No configurable settings.

### IPC

```sh
# Output (speaker)
noctalia msg set-volume 65
noctalia msg raise-volume
noctalia msg raise-volume 10
noctalia msg lower-volume
noctalia msg mute

# Input (microphone)
noctalia msg set-mic-volume 0.5
noctalia msg raise-mic-volume
noctalia msg raise-mic-volume 5%
noctalia msg lower-mic-volume
noctalia msg mute-mic
```

Volume and mic IPC use a default step of 5% when no explicit step is provided. Values and steps accept normalized (`0.0`–`1.0`) or percentage-style values (`65`, `65%`, `5%`). Rule of thumb: if you include a decimal and the value is `<= 1.0`, it is treated as normalized; otherwise it is treated as a percentage.

Output and mic volume are clamped to 0–100% by default. If `[audio] enable_overdrive = true`, the maximum is raised to 150%.

---

## `audio_visualizer`

Horizontal audio spectrum using the current PipeWire monitor stream.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `width` | number | `56` | Widget width in screen pixels |
| `height` | number | `16` | Widget height in screen pixels |
| `bands` | number | `16` | Number of spectrum bands |
| `mirrored` | bool | `false` | Mirror the spectrum around the center line |
| `low_color` | string | `"primary"` | Color for the first bars (theme role or `#` hex) |
| `high_color` | string | `"primary"` | Color for the last bars (theme role or `#` hex) |

```toml
[widget.audio-vis]
type       = "audio_visualizer"
width      = 64
height     = 16
bands      = 20
mirrored   = true
low_color  = "primary"
high_color = "secondary"
```

---

## `media`

Shows the current media artwork and track title from MPRIS.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `max_length` | number | `220` | Maximum length for the title text |
| `art_size` | number | `16` | Artwork size in pixels before scale |

```toml
[widget.media]
max_length = 220
art_size   = 24
```

---

## `battery`

Shows battery charge level and state via UPower. Hides itself when no battery is present — safe to include on desktops.

No configurable settings.

---

## `brightness`

Shows the current display brightness level and adjusts it via scroll wheel (±5% per step). Hides itself when no controllable display is found. Click opens the display tab in the control center.

No configurable settings. See [`[brightness]`](services.md#brightness) for backend configuration.

---

## `bluetooth`

Shows the Bluetooth adapter state and connected device. Click opens the Bluetooth tab in the control center.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `show_label` | bool | `false` | Show the connected device name next to the icon |

```toml
[widget.bluetooth]
show_label = true
```

---

## `network`

Shows the current network connection (Wi-Fi SSID and signal, or wired) via NetworkManager. Dims and shows a `wifi-off` glyph when disconnected.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `show_label` | bool | `true` | Show the SSID or interface name next to the glyph |

```toml
[widget.network]
show_label = false
```

---

## `keyboard_layout`

Shows the current keyboard layout indicator from the active XKB state.

Left-click cycles layouts using the compositor backend when supported. Override with `cycle_command` for a custom shell command.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `display` | string | `"short"` | `"short"` = compact code; `"full"` = full layout name |
| `cycle_command` | string | `""` | Optional override command run on left click instead of compositor backend |

```toml
[widget.keyboard_layout]
display = "short"   # short | full
```

---

## `lock_keys`

Shows Caps Lock / Num Lock / Scroll Lock state from the active XKB keyboard state.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `display` | string | `"short"` | `"short"` (`C N S`) or `"full"` (`Caps Num Scroll`) |
| `show_caps_lock` | bool | `true` | Show the Caps Lock indicator |
| `show_num_lock` | bool | `true` | Show the Num Lock indicator |
| `show_scroll_lock` | bool | `false` | Show the Scroll Lock indicator |
| `hide_when_off` | bool | `false` | Hide each indicator when it is off |

```toml
[widget.lock_keys]
display          = "short"
show_caps_lock   = true
show_num_lock    = true
show_scroll_lock = false
hide_when_off    = false
```

---

## `launcher`

Opens the launcher panel on click.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `icon` | string | `"search"` | Bar glyph id (Tabler-backed aliases) |

```toml
[widget.launcher]
icon = "menu"
```

---

## `weather`

Shows the current weather in the bar and opens the Weather control-center tab on click. Requires `[weather]` to be configured.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `max_length` | number | `160` | Maximum length for the weather text |
| `show_condition` | bool | `true` | Show condition text like `Overcast` next to temperature |

```toml
[widget.weather]
max_length     = 180
show_condition = false
```

---

## `notifications`

Shows the pending notification count. Right-clicking toggles transient Do Not Disturb (DND) mode.

No configurable settings.

### IPC

```sh
noctalia msg toggle-notification-dnd
noctalia msg notification-dnd-status
```

When DND is enabled, incoming notifications are stored in history/control center but toast popups are suppressed.

---

## `tray`

System tray (StatusNotifierItem).

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `hidden` | array of string | `[]` | Tray items to hide by id/name/bus/path token |

```toml
[widget.tray]
hidden = ["nm-applet", "blueman", "org.kde.StatusNotifierItem-1-1"]
```

---

## `power_profiles`

Shows the current power profile using a glyph and cycles to the next available profile on click.

No configurable settings.

---

## `idle_inhibitor`

Shows a keep-awake glyph and toggles the compositor idle inhibitor on click. Uses the standard Wayland `zwp_idle_inhibit_manager_v1` protocol.

No configurable settings.

### IPC

```sh
noctalia msg enable-idle-inhibitor
noctalia msg disable-idle-inhibitor
noctalia msg toggle-idle-inhibitor
```

---

## `nightlight`

Cycles through three night light states on click:

| State | Icon | Meaning |
|-------|------|---------|
| Off | moon-off | Night light disabled |
| On | moon | Scheduled — follows `start_time`/`stop_time` or location |
| Forced | moon-stars | Always-on override — ignores schedule |

No configurable settings.

### IPC

```sh
noctalia msg toggle-nightlight
noctalia msg toggle-force-nightlight
```

---

## `theme_mode`

Toggles between dark (moon glyph) and light (sun glyph) theme mode on click.

No configurable settings.

### IPC

```sh
noctalia msg toggle-theme-mode
```

---

## `session`

Shows a power glyph and opens the session menu panel on click.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `icon` | string | `"shutdown"` | Bar glyph id (Tabler-backed aliases) |

```toml
[widget.session]
icon = "lock"
```

---

## `wallpaper`

Shows a glyph and opens the wallpaper picker panel on click.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `icon` | string | `"wallpaper-selector"` | Bar glyph id (Tabler-backed aliases) |

```toml
[widget.wallpaper]
icon = "photo"
```
