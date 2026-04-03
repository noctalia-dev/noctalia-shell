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

### In Progress

- Notification daemon (DBus)
  - [x] Prevent duplicate stacking when replacing
  - [x] Actions implementation (D-Bus backend)
  - [x] Graceful shutdown (SIGTERM/SIGINT)
  - [ ] Display icon in UI layer (need Phase 1)
  - [ ] Closing/removal API polish

### Phase 1 -- Renderer completion

Everything else depends on these.

- [X] Retained scene graph (`Node`, `RectNode`, `TextNode`, `ImageNode`)
- [ ] Per-surface invalidation and property animations
- [ ] Image/texture loading
- [ ] Multi-monitor bar instances (one per output, hot-plug)
- [ ] Font fallback, DPI-aware metrics, text truncation

### Phase 2 -- Minimum viable bar

- [ ] Compositor integration (Niri, Hyprland)
- [ ] Workspaces widget
- [ ] Clock widget
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
- [ ] System stats (CPU, RAM, temperature)

### Phase 4 -- Desktop shell

Surfaces and interactions beyond the bar.

- [ ] MPRIS service (media player control)
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

- [ ] Color scheme generation (port our python implementation to c++, need proper test suite so it's 100% similar)
- [ ] Dark/light mode switching
- [ ] Wallpaper management
- [ ] Settings panel
- [ ] I18n / translations
- [ ] Blur and advanced visual effects
- [ ] Night light (wlsunset)
- [ ] Sound effects
- [ ] Toast notifications (is it really needed? or should we just unify everything in notifications)

### Phase 6 -- Ecosystem

- [ ] Plugin system
- [ ] Desktop widgets
- [ ] Update checker
- [ ] Calendar integration
- [ ] Geolocation (weather)

### Controls (`src/ui/controls/`)

Low-level UI building blocks, built incrementally as widgets need them.

- [ ] Label
- [ ] Container / box layout
- [ ] Icon
- [ ] Separator
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

- [ ] Workspace
- [ ] Clock
- [ ] Tray
- [ ] Volume
- [ ] Notification history
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
- [ ] Dark mode toggle
- [ ] Night light
- [ ] Keep awake (idle inhibitor)
- [ ] VPN
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
