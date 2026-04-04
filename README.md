Noctalia
===

A lightweight Wayland shell and bar with no Qt or GTK dependency.

## Design Principles

- Direct Wayland + OpenGL ES only -- no toolkit overhead
- Minimal scene graph, domain-specific to shell UI
- Packaging should work across all major Linux distros: Arch, NixOS, Fedora, Debian, Void, OpenSuse

## Stack

| Layer | Library |
|-------|---------|
| Wayland core | `libwayland-client`, `wayland-scanner`, `wayland-protocols` |
| Surfaces | `zwlr-layer-shell-v1` |
| Multi-monitor | `zxdg-output-unstable-v1` |
| Lockscreen | `ext-session-lock-v1` |
| Cursor | `wp-cursor-shape-v1` |
| Rendering | `EGL`, `OpenGL ES 3`, `wayland-egl` |
| Text | `freetype`, `harfbuzz`, `msdfgen` (vendored), `fontconfig` |
| IPC | `sdbus-c++` |
| Audio | `libpipewire` |
| Config | TBD |

## Build

Requires [just](https://github.com/casey/just).

```sh
git submodule update --init --recursive

# Debug (default)
just configure
just build

# Optimized release (-O3, LTO, native)
just configure release
just build

# Clean rebuild
just rebuild          # debug
just rebuild release  # release

# Run
just run

# Toggle verbose debug logs at runtime
gdbus call --session --dest dev.noctalia.Debug --object-path /dev/noctalia/Debug --method dev.noctalia.Debug.SetVerboseLogs false
gdbus call --session --dest dev.noctalia.Debug --object-path /dev/noctalia/Debug --method dev.noctalia.Debug.SetVerboseLogs true
```

<details>
<summary>Manual CMake</summary>

```sh
cmake -B build -DCMAKE_BUILD_TYPE=Debug   # or Release
cmake --build build --parallel
./build/noctalia
```
</details>

## Project Layout

```
src/
  app/           Application bootstrap, main loop
  core/          Logger, shared utilities
  dbus/          DBus service implementations
  font/          Font discovery (fontconfig)
  notification/  Notification manager
  render/        EGL/OpenGL renderer, shader programs, MSDF text
  shell/         Shell runtime
  wayland/       Wayland connection, layer-shell surfaces
  ui/
    controls/   Low-level UI building blocks
third_party/
  msdfgen/       MSDF glyph generation (git submodule)
```

## Roadmap

### Completed

- Wayland foundation, layer-shell surfaces, frame callbacks
- EGL/OpenGL ES renderer with shader pipeline
- GPU primitives: rounded rects (SDF), linear gradients, borders
- MSDF text rendering (FreeType + HarfBuzz + msdfgen atlas)
- Font discovery via fontconfig
- Structured logger (`std::format`-based)
- MPRIS backend complete (basic throttling for noisy player updates; proper coalescing should wait for the settled event-loop/timer model)
- Notification backend complete

### Phase 1 -- Renderer completion

Everything else depends on these.

- [x] Retained scene graph (`Node`, `RectNode`, `TextNode`, `ImageNode`)
- [x] Font fallback chain (fontconfig `FcFontSort`), DPI-aware buffer scaling, text truncation with ellipsis
- [x] Image/texture loading (stb_image + nanosvg, ARGB pixmap support, `TextureManager`)
- [x] Property animation system (easing functions, frame-callback driven `AnimationManager`)
- [x] Multi-monitor bar instances (one `LayerSurface` per output, hot-plug add/remove)

### Phase 2 -- Minimum viable bar

- [x] Compositor integration (ext-workspace)
- [X] Workspaces widget
- [X] Clock widget
- [X] Wallpaper management
- [ ] System tray (StatusNotifierItem via DBus)
- [ ] Audio service (Pipewire) + volume OSD
- [ ] Notification indicator + notification popup UI

### Phase 3 -- Hardware and networking

Status indicators and controls that make the bar complete.

- [ ] Battery service (UPower via DBus)
- [ ] Power profiles (power-profiles-daemon via DBus)
- [ ] Brightness control + OSD
- [ ] Network service (NetworkManager via DBus)
- [ ] Bluetooth service (Bluez via DBus)
- [ ] System stats (CPU, RAM, temperature) (backend logging started: cpu/ram/temp)

### Phase 4 -- Desktop shell

Surfaces and interactions beyond the bar.

- [x] MPRIS service discovery + metadata/state tracking
- [x] MPRIS transport controls
- [ ] Control center panel
- [ ] Keyboard layout switching
- [ ] PipeWire audio spectrum
- [ ] Clipboard manager
- [ ] Host/distro detection
- [ ] Application launcher / search
- [ ] Lock screen (ext-session-lock-v1)
- [ ] Idle inhibitor (prevent sleep)
- [ ] More compositors (Mango, Sway, Labwc)

### Phase 5 -- Theming and customization

- [ ] Palette generation (port python implementation to c++, need proper test suite so it's 100% similar with test images)
- [ ] Dark/light mode switching
- [ ] Settings panel
- [ ] I18n / translations
- [ ] Blur and advanced visual effects
- [ ] Night light (wlsunset)
- [ ] Sound effects

### Phase 6 -- Ecosystem

- [ ] Compositor integration (Hyprland)
- [ ] Plugin system
- [ ] Desktop widgets
- [ ] Update checker
- [ ] Calendar integration
- [ ] Geolocation (weather)

### Controls (`src/ui/controls/`)

Low-level UI building blocks, built incrementally as widgets need them.

- [X] Label
- [X] Box
- [X] Separator
- [X] Icon
- [ ] Toggle
- [ ] Button
- [ ] Slider
- [ ] Tooltip
- [ ] Progress bar
- [ ] Scroll view
- [ ] List view
- [ ] Text input
- [ ] Dropdown
- [ ] Checkbox
- [ ] Radio button
- [ ] Tab bar
- [ ] Grid view
- [ ] Context menu
- [ ] Color picker

### Bar Widgets

- [X] Workspace
- [X] Clock
- [ ] Tray
- [ ] Volume
- [ ] Notification button
- [ ] Battery
- [ ] Network
- [ ] Bluetooth
- [ ] Brightness
- [ ] Media mini
- [ ] Microphone
- [ ] Power profile
- [ ] System monitor
- [ ] Active window
- [ ] Taskbar
- [ ] Keyboard layout
- [ ] Lock keys (Caps/Num)
- [ ] Dark mode button
- [ ] Night light
- [ ] Keep awake (idle inhibitor)
- [ ] Audio visualizer
- [ ] Launcher button
- [ ] Control center button
- [ ] Session menu button
- [ ] Settings button
- [ ] Wallpaper selector button
- [ ] Custom button (user-defined IPC)
- [ ] Spacer

### Desktop Widgets

- [ ] Clock
- [ ] Media player
- [ ] System stats
- [ ] Audio visualizer
- [ ] Weather
