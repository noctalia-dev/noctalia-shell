# Wallpaper

```toml
[wallpaper]
enabled             = true
fill_mode           = "crop"    # center | crop | fit | stretch | repeat
fill_color          = "#111111" # optional fallback/fill color; image wallpapers take priority
transition          = ["fade", "wipe", "disc", "stripes", "zoom", "honeycomb"]
                                # array of effects picked at random each transition
                                # omit to use all effects
transition_duration = 1500      # milliseconds
edge_smoothness     = 0.3       # 0.0 – 1.0

# Directory browsed by the wallpaper picker panel
directory           = "/home/user/Wallpapers"
# Optional per-mode directories
directory_light     = "/home/user/Wallpapers/Light"
directory_dark      = "/home/user/Wallpapers/Dark"

[wallpaper.automation]
enabled                      = false
interval_minutes             = 30       # 0 = disable automation
order                        = "random" # random | alphabetical
recursive                    = true     # scan subdirectories when selecting random wallpapers

# Per-monitor overrides — same match rules as bar monitor overrides
[wallpaper.monitor.DP-2]
enabled         = false
fill_color      = "#202020"
directory       = "/home/user/Wallpapers/Vertical"
directory_light = "/home/user/Wallpapers/Vertical/Light"
directory_dark  = "/home/user/Wallpapers/Vertical/Dark"
```

The wallpaper picker panel lists images in `directory` as a grid of thumbnails. Selecting a monitor in the panel toolbar switches to that monitor's override directory (falling back to the base `directory`). Clicking a tile writes the path to `state.toml` and applies it immediately. Picking a wallpaper while **ALL** is selected applies it to every connected output. Picking a solid color stores it as a wallpaper source path such as `color:#FF00FF`, so it uses the same transition shader pipeline as image wallpapers.

`fill_color` accepts hex colors (`#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`) or theme role names such as `surface` and `primary`. It is used behind image wallpapers and in uncovered areas for `center`/`fit`.

Monitor overrides may also set `fill_color`.

When automation is enabled, Noctalia picks one image from `directory` on the configured interval and applies it to all connected outputs in sync.
`order = "random"` chooses a random image each cycle.
`order = "alphabetical"` sorts paths case-insensitively and advances to the next image each cycle (wrapping at the end).

---

# Overview

Renders a blurred and tinted copy of the current wallpaper as a layer-shell backdrop for compositor overview modes (e.g. niri's overview). Disabled by default.

To make the surface visible during niri overview, add a layer-rule to your niri config:

```kdl
layer-rule {
    match namespace="^noctalia-overview"
    place-within-backdrop true
}
```

```toml
[overview]
enabled                = false
unload_when_not_in_use = true   # release resources while closed; false keeps them warm in VRAM
blur_intensity         = 0.5    # 0.0 = no blur, 1.0 = maximum blur
tint_intensity         = 0.3    # 0.0 = no tint, 1.0 = fully opaque tint
```

The tint color is `palette.surface` and is not currently configurable.
