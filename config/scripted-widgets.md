# Scripted Widgets

Custom bar widgets driven by [Luau](https://luau.org) scripts. A script controls a widget's glyph, label, and colors, and can run shell commands, send notifications, and read config settings.

## Configuration

```toml
[widget.my_widget]
type   = "scripted"
script = "~/.config/noctalia/scripts/my_widget.lua"
# any extra keys are readable from Lua via barWidget.getConfig()
my_setting = "value"
```

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `script` | string | `""` | Path to the Luau script file. Absolute paths and `~` paths are used directly; relative paths are resolved from the assets bundle (e.g. `scripts/screen_recorder.lua`). |

---

## Lua API

### `noctalia.*` — general utilities

| Function | Returns | Description |
|----------|---------|-------------|
| `noctalia.log(msg)` | — | Log a message to shell debug output |
| `noctalia.runAsync(cmd)` | `boolean` | Execute a shell command asynchronously (fire-and-forget). Returns true if the process was launched. |
| `noctalia.runSync(cmd)` | `exitCode, stdout, stderr` | Execute a shell command synchronously. Returns exit code (number), stdout (string), stderr (string). |
| `noctalia.commandExists(name)` | `boolean` | Check if a command exists in PATH |
| `noctalia.notify(title, body?)` | — | Show an internal notification (normal urgency) |
| `noctalia.notifyError(title, body?)` | — | Show an internal notification (critical urgency) |
| `noctalia.getenv(name)` | `string?` | Read an environment variable. Returns nil if unset. |

### `barWidget.*` — widget display

| Function | Returns | Description |
|----------|---------|-------------|
| `barWidget.setText(text)` | — | Set the label text |
| `barWidget.setGlyph(name)` | — | Set the icon by Tabler icon name |
| `barWidget.setGlyphCodepoint(cp)` | — | Set the icon by Unicode codepoint |
| `barWidget.setColor(role)` | — | Set the label color by theme role |
| `barWidget.setGlyphColor(role)` | — | Set the glyph color by theme role |
| `barWidget.setVisible(visible)` | — | Show or hide the entire widget |
| `barWidget.getConfig(key, default?)` | `any` | Read a TOML config setting. Returns the typed value or default/nil. |

**Theme color roles:** `primary`, `on_primary`, `secondary`, `on_secondary`, `tertiary`, `on_tertiary`, `error`, `on_error`, `surface`, `on_surface`, `surface_variant`, `on_surface_variant`, `outline`, `shadow`, `hover`, `on_hover`.

### Lua callbacks

| Callback | Called when |
|----------|------------|
| `update()` | Every ~250ms while the widget is visible |
| `onClick()` | Left mouse button clicked |
| `onRightClick()` | Right mouse button clicked |
| `onMiddleClick()` | Middle mouse button clicked |
| `onHover(isHovering)` | Mouse enters (`true`) or leaves (`false`) the widget |

---

## Scene graph

Every scripted widget has the following node tree:

```
InputArea (accepts left / right / middle clicks)
  └─ Flex (horizontal, center-aligned)
      ├─ Glyph (hidden until setGlyph/setGlyphCodepoint is called)
      └─ Label
```

`setVisible(false)` hides the entire `InputArea` root.

---

## Example: GPU screen recorder

A `screen_recorder.lua` script is bundled in `assets/scripts/` that wraps `gpu-screen-recorder` with recording and replay buffer support.

- **Left click** — toggle recording
- **Right click** — toggle replay buffer (if enabled) or save replay (if active)
- **Middle click** — save replay buffer

```toml
[widget.screen_recorder]
type             = "scripted"
script           = "scripts/screen_recorder.lua"
directory        = ""
filename_pattern = "recording_%Y%m%d_%H%M%S"
video_source     = "portal"
video_codec      = "h264"
audio_codec      = "opus"
audio_source     = "default_output"
quality          = "very_high"
frame_rate       = 60
color_range      = "limited"
resolution       = "original"
show_cursor      = true
copy_to_clipboard = false
restore_portal   = false
replay_enabled   = false
replay_duration  = 30
replay_storage   = "ram"
hide_inactive    = false
```

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `directory` | string | `""` | Output directory (empty = `~/Videos`) |
| `filename_pattern` | string | `"recording_%Y%m%d_%H%M%S"` | strftime pattern for filenames |
| `video_source` | string | `"portal"` | `portal`, `screen`, or `focused-monitor` (Hyprland) |
| `video_codec` | string | `"h264"` | `h264`, `hevc`, `av1`, `vp8`, `vp9` |
| `audio_codec` | string | `"opus"` | `opus` or `aac` |
| `audio_source` | string | `"default_output"` | `none`, `default_output`, `default_input`, `both` |
| `quality` | string | `"very_high"` | `medium`, `high`, `very_high`, `ultra` |
| `frame_rate` | number | `60` | Recording frame rate |
| `color_range` | string | `"limited"` | `limited` or `full` |
| `resolution` | string | `"original"` | `original`, `1920x1080`, `2560x1440`, etc. |
| `show_cursor` | bool | `true` | Include mouse cursor in recording |
| `copy_to_clipboard` | bool | `false` | Copy file URI to clipboard after recording |
| `restore_portal` | bool | `false` | Restore previous XDG portal session |
| `replay_enabled` | bool | `false` | Enable replay buffer support |
| `replay_duration` | number | `30` | Replay buffer duration in seconds |
| `replay_storage` | string | `"ram"` | `ram` or `disk` |
| `hide_inactive` | bool | `false` | Hide widget when not recording or replaying |
