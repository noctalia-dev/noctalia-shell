# Dock

A standalone application dock that displays pinned and running apps. Disabled by default.

```toml
[dock]
enabled             = false      # set true to activate
position            = "bottom"   # top | bottom | left | right
active_monitor_only = false      # when true, only show apps/windows from the active monitor

icon_size           = 48
padding             = 8          # inner padding around the icon row (all sides)
item_spacing        = 6          # gap between items in pixels
background_opacity  = 0.88
background_blur     = true       # request compositor blur via ext-background-effect-v1 (niri)
shadow              = true       # cast the global [shell.shadow]
radius              = 16
margin_h            = 0          # horizontal compositor margin
margin_v            = 8          # vertical gap between dock and screen edge

show_running        = true       # also show running apps not in the pinned list
auto_hide           = false      # fade out when pointer leaves; fade in on approach
reserve_space       = false      # keep exclusive zone even when auto-hidden

active_scale        = 1.0        # icon scale for the focused app (clamped 0.1–1.75)
inactive_scale      = 0.85       # icon scale for non-focused apps (clamped 0.1–1.0)
active_opacity      = 1.0
inactive_opacity    = 0.85
show_instance_count = true       # badge with window count when an app has 2+ windows

# Desktop entry IDs, StartupWMClass, or human-readable names
pinned = ["firefox", "code", "kitty"]
```

Shadow blur, offset, and alpha are global under `[shell.shadow]`. The dock only exposes `shadow = true|false`.

---

## `pinned` matching

Each entry in `pinned` is matched against desktop entries using these rules in order:

1. Desktop entry ID stem (`"firefox"` matches `firefox.desktop` and `org.mozilla.Firefox.desktop`)
2. `StartupWMClass` field of the desktop entry
3. App `Name` field (case-insensitive)
4. Full desktop entry path

If no match is found, a placeholder slot is reserved so the dock position is preserved.

---

## Active app emphasis

- The focused app uses `active_scale` and `active_opacity`.
- All other apps use `inactive_scale` and `inactive_opacity`.
- Focus changes animate smoothly between the two states.

---

## Auto-hide

When `auto_hide = true`, the dock:
- Does **not** reserve compositor exclusive zone.
- Fades out after the pointer leaves (slow ease-in animation).
- Fades back in when the pointer enters the thin edge trigger strip.

Set `reserve_space = true` to keep the exclusive zone while auto-hidden.

---

## IPC

```sh
noctalia msg show-dock       # re-display all instances
noctalia msg hide-dock       # close all instances until next reload
noctalia msg toggle-dock     # toggle dock visibility
noctalia msg reload-dock     # reload dock configuration
```
