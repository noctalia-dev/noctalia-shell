# Services

- [Audio](#audio)
- [Brightness](#brightness)
- [Night Light](#night-light)
- [Weather](#weather)
- [Idle](#idle)
- [Notifications](#notifications)

---

## Audio

```toml
[audio]
enable_overdrive = false   # allow volume sliders above 100% (up to 150%)
```

When `enable_overdrive = false`, the Control Center output and microphone sliders clamp to 100%. When `true`, they allow up to 150%.

---

## Brightness

Brightness control uses the kernel backlight interface by default. `ddcutil` support is opt-in for external monitors that expose DDC/CI brightness.

```toml
[brightness]
enable_ddcutil = false
ignore_mmids   = []   # e.g. ["ACI-ROG_PG279Q-10220"] — skip in all ddcutil commands

[brightness.monitor.eDP-1]
backend = "backlight"   # auto | none | backlight | ddcutil

[brightness.monitor.DP-1]
backend = "ddcutil"
```

Notes:
- `enable_ddcutil = true` only enables DDC/CI discovery — it does not force every monitor to `ddcutil`.
- `ignore_mmids` passes `--ignore-mmid` to every `ddcutil` invocation. Run `ddcutil --verbose detect` to find monitor model id strings.
- Per-monitor overrides use the same connector/description matching rules as bar monitor overrides.
- `backend = "auto"` prefers kernel backlight when available and falls back to `ddcutil`.
- `backend = "none"` hides brightness control for the matched display.
- `ddcutil` is treated as best-effort — repeated DDC failures cool down that display to avoid hammering the monitor bus.

### IPC

```sh
noctalia msg set-brightness 65           # current display
noctalia msg set-brightness DP-1 0.65
noctalia msg set-brightness * 40%        # all displays

noctalia msg raise-brightness            # current display, default 5% step
noctalia msg raise-brightness DP-1 10
noctalia msg lower-brightness * 5%       # all displays
```

Targets: `current`, `all`/`*`, a display id (`eDP-1`, `DP-1`), or a monitor selector token (same matching rules as monitor overrides). `current` resolves from the active/focused output, falling back to the last interactive output.

Values and steps accept normalized (`0.0`–`1.0`) or percentage-style (`65`, `65%`, `5%`) values. `raise-brightness` / `lower-brightness` target `current` with a 5% step when no arguments are given.

---

## Night Light

Uses `wlsunset` to apply color temperature shifts.

```toml
[nightlight]
enabled              = false
force                = false   # force night mode from startup
use_weather_location = true    # use weather coordinates when no manual schedule or location is set

temperature_day   = 6500       # Kelvin
temperature_night = 4000       # Kelvin

# Option A: explicit schedule
start_time = "20:30"           # HH:MM — sunset / night starts
stop_time  = "07:30"           # HH:MM — sunrise / day starts

# Option B: geolocation schedule (used when start/stop are missing)
# latitude  = 52.5200
# longitude = 13.4050
```

Priority: `start_time` + `stop_time` > explicit `latitude`/`longitude` > WeatherService coordinates. If only one of latitude/longitude is provided, Night Light refuses to start.

### IPC

```sh
noctalia msg enable-nightlight
noctalia msg disable-nightlight
noctalia msg toggle-nightlight
noctalia msg toggle-force-nightlight
```

`enable-nightlight` / `disable-nightlight` / `toggle-nightlight` control schedule enable state. `toggle-force-nightlight` toggles forced-on mode regardless of schedule.

---

## Weather

```toml
[weather]
enabled         = false
auto_locate     = false         # resolve coordinates from IP address when true
address         = "Toronto, ON" # geocoded when auto_locate = false
refresh_minutes = 30
unit            = "celsius"     # celsius | fahrenheit
```

When `auto_locate = false`, Noctalia geocodes `address` to latitude/longitude and fetches current weather plus a 6-day forecast. When `auto_locate = true`, the `address` field is ignored and location is resolved via IP.

Enabling weather adds a `Weather` tab to the control center. The bar `weather` widget type also requires weather to be enabled.

---

## Idle

Idle behaviors are named entries under `[idle.behavior.*]`. When no `config.toml` exists, Noctalia uses a built-in default with the lock behavior disabled.

```toml
[idle.behavior.lock]
timeout = 660
command = "noctalia:lock"
enabled = false             # explicitly disabled in the default config

[idle.behavior.screen-off]
timeout = 32
command = "noctalia:dpms-off"

[idle.behavior.custom]
timeout = 48
command = "notify-send 'Idle' 'Going idle'"
```

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `enabled` | bool | `true` | Enable or disable this behavior |
| `timeout` | int | `0` | Seconds before the behavior triggers |
| `command` | string | `""` | Shell command or `noctalia:` IPC subcommand |

### `noctalia:` commands in idle

The `noctalia:` prefix runs the rest of the string through the IPC command registry — the same as `noctalia msg <subcommand>`. Examples:

```
noctalia:lock
noctalia:dpms-off
noctalia:dpms-on
noctalia:enable-idle-inhibitor
noctalia:disable-idle-inhibitor
noctalia:toggle-idle-inhibitor
noctalia:panel-toggle launcher
noctalia:panel-toggle session
noctalia:panel-toggle clipboard
noctalia:panel-toggle wallpaper
noctalia:panel-toggle control-center
```

Idle behavior uses the Wayland `ext_idle_notifier_v1` protocol and respects active idle inhibitors.

---

## Notifications

```toml
[notification]
enable_daemon      = true   # when false, don't claim org.freedesktop.Notifications; internal notifications still work
background_opacity = 0.97   # toast card background alpha; lower values let compositor blur show through
background_blur    = true   # request compositor background blur behind toasts
```
