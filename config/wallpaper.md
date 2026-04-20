# Wallpaper

```toml
[wallpaper]
enabled             = true
fill_mode           = "crop"    # center | crop | fit | stretch | repeat
transition          = ["fade", "wipe", "disc", "stripes", "zoom", "honeycomb"]
                                # array of effects picked at random each transition
                                # omit to use all effects
transition_duration = 1500      # milliseconds
edge_smoothness     = 0.3       # 0.0 – 1.0

# Directory browsed by the wallpaper picker panel
directory           = "/home/user/Wallpapers"
# Optional per-mode directories (parsed but not yet consumed by the renderer)
directory_light     = "/home/user/Wallpapers/Light"
directory_dark      = "/home/user/Wallpapers/Dark"

# Per-monitor overrides — same match rules as bar monitor overrides
[wallpaper.monitor.DP-2]
enabled         = false
directory       = "/home/user/Wallpapers/Vertical"
directory_light = "/home/user/Wallpapers/Vertical/Light"
directory_dark  = "/home/user/Wallpapers/Vertical/Dark"
```

The wallpaper picker panel lists images in `directory` as a grid of thumbnails. Selecting a monitor in the panel toolbar switches to that monitor's override directory (falling back to the base `directory`). Clicking a tile writes the path to `state.toml` and applies it immediately. Picking a wallpaper while **ALL** is selected applies it to every connected output.

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
