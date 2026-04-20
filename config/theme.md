# Theme

Controls the colors used across the shell — bars, panels, widgets, OSD, overview, and notifications.

```toml
[theme]
mode              = "dark"        # dark | light | auto
source            = "builtin"     # builtin | wallpaper | community
builtin           = "Noctalia"    # bundled scheme name
community_palette = "Noctalia"    # community palette name when source = "community"
wallpaper_scheme  = "m3-content"  # generator used when source = "wallpaper"
```

Theme changes apply live when you edit `config.toml`. Wallpaper-derived themes re-resolve automatically when the default wallpaper changes.

---

## `source`

| Value | Description |
|-------|-------------|
| `builtin` | Use one of the schemes compiled into the binary. |
| `wallpaper` | Generate a palette from the current default wallpaper each time it changes. |
| `community` | Fetch a palette by name from `https://api.noctalia.dev/palette/<name>`. |

---

## `builtin`

Names which bundled scheme to load when `source = "builtin"`. Unknown names fall back to `Noctalia`.

Available schemes: `Ayu`, `Catppuccin`, `Dracula`, `Eldritch`, `Gruvbox`, `Kanagawa`, `Noctalia`, `Nord`, `Rosé Pine`, `Tokyo-Night`

---

## `community_palette`

Names a palette served by `https://api.noctalia.dev/palette/<name>`. The shell downloads the palette on first use and caches it in `~/.cache/noctalia/community-palettes/` (honoring `XDG_CACHE_HOME`). Subsequent launches load the cached file and never touch the network, so community palettes work offline.

While the initial download is in flight — or if it fails — the shell falls back to `Noctalia` built-in and cross-fades once the download arrives.

To refresh a palette, delete the corresponding file under `~/.cache/noctalia/community-palettes/`.

---

## `wallpaper_scheme`

Picks the generator when `source = "wallpaper"`:

| Value | Description |
|-------|-------------|
| `m3-tonal-spot` | M3 default — balanced tones anchored on the seed color |
| `m3-content` | M3 for content-forward UIs — higher chroma |
| `m3-fruit-salad` | M3 with playful cross-hue accents |
| `m3-rainbow` | M3 spanning the full wheel for multi-accent layouts |
| `m3-monochrome` | M3 collapsed to a single hue |
| `vibrant` | Custom — saturated and high-contrast |
| `faithful` | Custom — stays close to the source image |
| `dysfunctional` | Custom — deliberately off-kilter |
| `muted` | Custom — low-saturation |

---

## `mode`

`dark` or `light` selects the palette variant. `auto` is treated as `dark` until system light/dark tracking lands.

### IPC

```sh
noctalia msg toggle-theme-mode
```

---

## External App Templates

Noctalia can apply generated colors to external app config files whenever the resolved theme changes.

```toml
[theme.templates]
enable_builtins       = true
builtin_ids           = []        # opt-in; run: noctalia theme --list-builtins
enable_user_templates = false
user_config           = "~/.config/noctalia/user-templates.toml"
```

- `enable_builtins` enables the shipped built-in template catalog.
- `builtin_ids` selects which built-in templates run. Empty array = nothing applied until you opt in.
- `enable_user_templates` enables loading your own template file.
- `user_config` points at that extra file. When enabled, Noctalia creates a stub if it does not already exist.

```toml
[theme.templates]
enable_builtins       = true
builtin_ids           = ["foot", "walker", "gtk3", "gtk4"]
enable_user_templates = true
user_config           = "~/.config/noctalia/user-templates.toml"
```

List available built-in template ids:

```sh
noctalia theme --list-builtins
```
