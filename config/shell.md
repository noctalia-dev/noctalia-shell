# Shell

- [Shell settings](#shell-settings)
- [OSD](#osd)
- [Keybinds](#keybinds)
- [Hooks](#hooks)

---

## Shell settings

Global UI settings that apply across all shell surfaces.

```toml
[shell]
ui_scale              = 1.0             # content scale for panels and non-bar shell UI
font_family           = "sans-serif"    # Pango family string; Fontconfig handles fallback
lang                  = "en"            # override language detection
offline_mode          = false           # block all outgoing HTTP requests
telemetry_enabled     = false           # anonymous startup ping
polkit_agent          = false           # register Noctalia's native polkit authentication agent
password_style        = "default"       # default | random
avatar_path           = "~/Pictures/avatar.png"
settings_show_advanced = false          # show advanced settings by default in Settings
show_location         = true            # show weather location text in shell UI
clipboard_auto_paste  = "auto"          # off | auto | ctrl_v | ctrl_shift_v | shift_insert

[shell.animation]
enabled = true
speed   = 1.0   # 1.0 = normal, 0.5 = 2× slower, 2.0 = 2× faster

[shell.shadow]
blur     = 12    # global surface shadow blur radius; 0 disables all rendered surface shadows
offset_x = 2
offset_y = 2     # positive = down
alpha    = 0.55  # multiplied by each component's background opacity

[shell.panel]
background_blur = true   # request compositor blur behind panels via ext-background-effect-v1

[shell.mpris]
blacklist = []           # optional list of players to hide from media widgets/control-center
```

Notes:
- `ui_scale` is completely separate from `bar.scale`: `bar.scale` only affects bar widget content; `ui_scale` covers the control center, launcher, clipboard, and other non-bar surfaces. Neither changes Wayland output / HiDPI buffer scale.
- `font_family` sets the primary Pango family for all shell text. Can be a concrete family like `Inter` or a generic like `sans-serif`.
- `offline_mode` prevents the shell from making any outgoing HTTP requests (weather, community palettes, album art, remote notification icons). Distro packagers can default to `true` to comply with policies requiring explicit user consent for network access.
- `telemetry_enabled` sends a single anonymous POST to `api.noctalia.dev/ping` on each startup containing: a random instance ID, shell version, compositor name, OS name, RAM, monitor resolutions, and UI scale. No personal data is collected. The instance ID is a random UUID stored in `~/.local/state/noctalia/instance.id`.
- `polkit_agent` controls registration on `org.freedesktop.PolicyKit1`. Keep disabled if another desktop agent handles auth prompts.
- Notification daemon ownership moved out of `[shell]`: use `[notification].enable_daemon` in `config/services.md`.
- `password_style`: `default` uses `circle-filled`; `random` cycles through multiple filled glyph shapes on polkit and lock screen inputs.
- `settings_show_advanced`: when `true`, Settings opens with advanced entries visible.
- `show_location`: when `false`, weather location text/coordinates are hidden in shell surfaces.
- `clipboard_auto_paste`: `auto` = image entries use `Ctrl+V`, text entries use `Ctrl+Shift+V`; `off` = copy only, no automatic paste.
- `shell.animation.enabled` disables all animated transitions globally. `speed` scales durations globally.
- `shell.shadow` defines the shared shadow metrics for shell surfaces. Components such as bars and the dock only opt in/out with `shadow = true|false`; they do not define their own blur or offset.
- `shell.panel.background_blur` toggles compositor blur on every shell panel (control center, launcher, clipboard, attached menus, etc.). Inert on compositors that do not implement `ext-background-effect-v1`.
- `shell.mpris.blacklist` excludes matching MPRIS players from Noctalia media UI and active-player selection. Entries are case-insensitive and match player bus name, identity, desktop entry, or a bus-name substring token (for example `"spotify"`).

---

## OSD

```toml
[osd]
position = "top_right"   # top_right | top_left | top_center | bottom_right | bottom_left | bottom_center
```

The OSD powers the volume HUD and defaults to `top_right`.

---

## Keybinds

Centralized keyboard actions for shell panels (`launcher`, `session`, `clipboard`, `wallpaper`) and panel close/cancel.

```toml
[keybinds]
validate = ["return", "kp_enter"]
cancel   = ["escape"]
left     = ["left"]
right    = ["right"]
up       = ["up"]
down     = ["down"]
```

Each action accepts a single string chord or an array of chords.

**Chord format:** `key`, `modifier+key`, or `modifier+modifier+key`

**Supported modifiers:** `ctrl`, `shift`, `alt`

**`super` bindings are rejected** (`super`, `win`, `windows`, `logo`, `meta`, `mod4`) and produce a config parse error.

**Supported actions:** `validate`, `cancel`, `left`, `right`, `up`, `down`

---

## Hooks

Optional shell hooks run commands when specific events happen. Define them under `[hooks]` in `config.toml`. Each event is a string (one command) or an array of strings (run in order). The same `noctalia:` prefix rules apply as in [idle behaviors](services.md#idle).

| Key | When it fires |
|-----|---------------|
| `started` | Once after Noctalia finishes startup (IPC ready). |
| `wallpaper_changed` | After a persisted wallpaper path change is applied. |
| `colors_changed` | After the theme palette is resolved and terminal templates are updated. |
| `session_locked` | When the compositor confirms the session lock. |
| `session_unlocked` | When the session leaves the locked state. |
| `logging_out` | Immediately before the session panel runs the logout sequence. |
| `rebooting` | Immediately before the session panel runs reboot. |
| `shutting_down` | Immediately before the session panel runs shutdown. |
| `wifi_enabled` / `wifi_disabled` | When NetworkManager's Wi-Fi radio toggles (not on first snapshot). |
| `bluetooth_enabled` / `bluetooth_disabled` | When the default adapter's powered state toggles (not on first snapshot). |
| `battery_state_changed` | When UPower's battery state enum changes (charging, discharging, etc.). Sets `NOCTALIA_BATTERY_STATE` (e.g. `Charging`, `Discharging`, `Charged`). |
| `battery_under_threshold` | When charge **crosses from above to at or below** `battery_low_percent_threshold`. Sets `NOCTALIA_BATTERY_PERCENT`. |

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `battery_low_percent_threshold` | int | `0` | Percent (0–100). `0` disables `battery_under_threshold`. Set to e.g. `15` to activate. |

```toml
[hooks]
started           = "notify-send 'Noctalia' 'Shell started'"
wallpaper_changed = ["touch /tmp/noctalia-wallpaper"]
colors_changed    = "notify-send 'Theme' 'Palette updated'"

session_locked   = "notify-send 'Session' 'Locked'"
session_unlocked = "notify-send 'Session' 'Unlocked'"

logging_out   = "echo logging out >> /tmp/noctalia-hooks.log"
rebooting     = "notify-send 'System' 'Rebooting'"
shutting_down = "notify-send 'System' 'Shutting down'"

wifi_enabled  = "notify-send 'Network' 'Wi-Fi on'"
wifi_disabled = "notify-send 'Network' 'Wi-Fi off'"

bluetooth_enabled  = "notify-send 'BT' 'Bluetooth on'"
bluetooth_disabled = "notify-send 'BT' 'Bluetooth off'"

battery_low_percent_threshold = 15
battery_state_changed   = "notify-send 'Power' \"Battery: $NOCTALIA_BATTERY_STATE\""
battery_under_threshold = "notify-send 'Power' \"Battery at ${NOCTALIA_BATTERY_PERCENT}%\""
```
