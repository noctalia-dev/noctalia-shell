# Control Center

## Shortcuts

The overview tab displays a row of shortcut buttons at the bottom. Up to 6 shortcuts are shown.

```toml
[[control_center.shortcuts]]
type = "wifi"

[[control_center.shortcuts]]
type = "bluetooth"

[[control_center.shortcuts]]
type = "nightlight"

[[control_center.shortcuts]]
type = "notification"

[[control_center.shortcuts]]
type = "wallpaper"

[[control_center.shortcuts]]
type = "session"
```

### Shortcut entry fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `type` | string | *required* | Shortcut type from the list below |
| `label` | string | (per type) | Override the default label |
| `icon` | string | (per type) | Override the default glyph name |

### Available shortcut types

| Type | Label | Behavior | Right-click |
|------|-------|----------|-------------|
| `wifi` | Wi-Fi | Toggle wireless on/off | Open network tab |
| `bluetooth` | Bluetooth | Toggle adapter on/off | Open bluetooth tab |
| `nightlight` | Night Light | Toggle blue-light filter | -- |
| `notification` | DND | Toggle Do Not Disturb | Open notifications tab |
| `dark_mode` | Dark Mode | Toggle light/dark theme | -- |
| `idle_inhibitor` | Idle Inhibitor | Toggle idle/sleep prevention | -- |
| `audio` | Audio | Toggle output mute | Open audio tab |
| `mic_mute` | Microphone | Toggle mic mute | Open audio tab |
| `power_profile` | Current profile | Cycle power profile | Open system tab |
| `media` | Media | Play/Pause active player | Open media tab |
| `weather` | Temperature | Open weather tab | Open weather tab |
| `sysmon` | System | Open system tab | Open system tab |
| `keyboard_layout` | Current layout | Cycle keyboard layout | -- |
| `wallpaper` | Wallpaper | Open wallpaper panel | -- |
| `session` | Session | Open session panel | -- |
| `clipboard` | Clipboard | Open clipboard panel | -- |

Toggle shortcuts show an active/inactive visual state. `power_profile`, `weather`, and `keyboard_layout` display dynamic labels (current profile, temperature, or layout name).

When no `[[control_center.shortcuts]]` entries are defined, the default set is: `wifi`, `bluetooth`, `nightlight`, `notification`, `wallpaper`, `session`.
