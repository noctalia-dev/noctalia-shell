# Bar

Bars are defined as named subtables under `[bar.*]`. Each bar is spawned on every connected output, then per-monitor overrides are applied.

```toml
[bar.main]
position           = "top"       # top | bottom | left | right
enabled            = true
auto_hide          = false       # slide out after pointer leaves; reveal from edge trigger strip
reserve_space      = false       # keep exclusive zone even when auto-hidden

thickness          = 34          # bar cross-axis size in pixels (height for horizontal, width for vertical)
background_opacity = 1.0         # 0.0 (transparent) to 1.0 (opaque)
background_blur    = true        # request compositor blur via ext-background-effect-v1 (niri)
radius             = 12          # global corner radius fallback
radius_top_left    = 12
radius_top_right   = 12
radius_bottom_left = 12
radius_bottom_right = 12
margin_h           = 180         # horizontal gap between bar and screen edge
margin_v           = 10          # vertical gap between bar and screen edge
padding            = 14          # main-axis padding from bar edges to start/end widget sections
widget_spacing     = 6           # gap between widgets within a section
scale              = 1.0         # content scale multiplier for icons and text

shadow_blur        = 12          # blur radius in pixels (0 = no shadow)
shadow_offset_x    = 0
shadow_offset_y    = 6           # positive = down

# Default capsule style for all widgets on this bar (see Widget Capsule section)
capsule            = false
capsule_fill       = "surface_variant"
capsule_opacity    = 1.0
# capsule_border   = "outline"   # omit this key for no border by default

start  = ["launcher", "wallpaper", "workspaces"]
center = ["clock"]
end    = ["media", "tray", "notifications", "network", "bluetooth", "volume", "brightness", "battery", "session"]
```

Radius precedence: `radius` is the global fallback; per-corner values override it when provided.

Multiple `[bar.*]` entries are supported — each is independently configured and rendered on all outputs.

---

## Per-monitor overrides

Inside a bar, add named monitor subtables under `[bar.<name>.monitor.*]`. **First match wins**, in file order.

```toml
[bar.main.monitor.dp1]
match              = "DP-1"    # connector name or description substring
enabled            = true
thickness          = 44
background_opacity = 0.9
radius             = 0
radius_top_left    = 12
radius_top_right   = 12
radius_bottom_left = 0
radius_bottom_right = 0
padding            = 20
widget_spacing     = 6
start              = []
center             = ["workspaces"]
end                = ["volume", "clock"]
```

**`match` resolution** — compared against:
1. Exact connector name (`eDP-1`, `DP-1`, `HDMI-A-1`, …)
2. Any substring of the monitor description string (`"LG"`, `"4K"`, `"DELL"`, …)

`match` defaults to the subtable key name when omitted, so `[bar.main.monitor."DP-1"]` without a `match` field works too.

Only the fields you specify are overridden; everything else falls through to the `[bar.*]` defaults. Supported override fields: all bar fields, plus `auto_hide`, `reserve_space`, `scale`, `background_opacity`, `color`, and all `capsule_*` keys.

---

## Auto-hide

When `auto_hide = true`, the bar:
- Does **not** reserve compositor exclusive zone (windows are not pushed away).
- Slides out once the pointer leaves the bar.
- Slides back in when the pointer reaches the matching screen edge trigger strip.

Set `reserve_space = true` to keep the exclusive zone while auto-hidden.

---

## Widget Capsule

Each widget can have a capsule (pill-shaped background + optional border). Settings cascade from bar defaults down to per-widget overrides.

### Bar-level defaults

Set under `[bar.<name>]` or `[bar.<name>.monitor.*]`:

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `capsule` | bool | `false` | `true` gives every widget a capsule unless `[widget.*]` sets `capsule = false`. |
| `color` | string | *(unset)* | Default icon + label color for every widget on this bar. |
| `capsule_fill` | string | `surface_variant` | Default capsule background. Theme role or `#` hex; hex alpha is ignored — use `capsule_opacity`. |
| `capsule_color` | string | — | Synonym for `capsule_fill` when that key is absent. |
| `capsule_foreground` | string | *(unset)* | Default icon + label color for capped widgets. `capsule_ink` is accepted as a deprecated alias. |
| `capsule_padding` | number | `6` | Inner padding in logical pixels before `scale` is applied (clamped 0–48). |
| `capsule_opacity` | number | `1.0` | Capsule background opacity (0.0–1.0). |
| `capsule_border` | string | *(omitted)* | If omitted, no border by default. If present (even `""`), per-widget border rules apply. |

### Per-widget overrides

Set under `[widget.<name>]`:

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `capsule` | bool | *(from bar)* | Omit to inherit bar flag; `false` disables; `true` forces on. |
| `capsule_fill` | string | *(from bar)* | Capsule background color. |
| `capsule_color` | string | *(from bar)* | Synonym for `capsule_fill` when that key is absent. |
| `capsule_foreground` | string | *(from bar)* | Icon + label color when capsule is visible. `color` takes priority over this. |
| `capsule_padding` | number | *(from bar)* | Per-widget inner padding (0–48). |
| `capsule_opacity` | number | *(from bar)* | Per-widget capsule background opacity. |
| `capsule_border` | string | *(from bar)* | Omit to inherit bar policy. Present but empty/whitespace-only = no border. |
| `color` | string | *(unset)* | Icon + label color with or without capsule. Resolution order: `color` → `capsule_foreground` → built-in defaults. |

Theme role names use **snake_case** (e.g. `on_surface`, `surface_variant`, `secondary`). Hyphens are accepted and normalized to underscores.

The capsule is hidden automatically when a widget reports no visible ink (empty tray, absent battery, invisible root). Subclasses may override `Widget::shouldShowBarCapsule()`.

```toml
[bar.main]
capsule         = true
capsule_fill    = "surface_secondary"
capsule_opacity = 0.9
capsule_border  = "outline"

# Accent bar: primary fill + matching text
[bar.accent]
capsule            = true
capsule_color      = "primary"
capsule_foreground = "on_primary"
capsule_padding    = 10

[widget.volume]
capsule_fill   = "#2a2a33"
capsule_border = ""          # no border on this widget

[widget.spacer]
type    = "spacer"
capsule = false
```
