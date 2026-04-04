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
| Images | `stb_image` (vendored), `nanosvg` (vendored) |
| IPC | `sdbus-c++` |
| Audio | `libpipewire` |
| Config | `tomlplusplus` (vendored) |

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

## Code Style

This project uses [clang-format](https://clang.llvm.org/docs/ClangFormat.html) for formatting. Run `just format` before committing.

## Project Layout

```
src/
  app/           Application bootstrap, main loop
  config/        Configuration and state persistence (TOML)
  core/          Logger, shared utilities
  dbus/          DBus service implementations
  debug/         Debug service (runtime log toggling)
  font/          Font discovery (fontconfig)
  notification/  Notification manager
  render/        EGL/OpenGL renderer, shader programs, MSDF text
  shell/         Shell runtime, bar and wallpaper
  system/        System monitor (CPU, RAM, temperature)
  time/          Time service and polling
  ui/
    controls/    Low-level UI building blocks
    icons/       Icon registry
    style/       Palette and styling
  wayland/       Wayland connection, layer-shell surfaces
third_party/
  msdfgen/       MSDF glyph generation (git submodule)
  tomlplusplus/  TOML parser (vendored)
  stb/           Image loading (vendored)
  nanosvg/       SVG rasterization (vendored)
```

## Roadmap

### Bar completion

- [~] System tray (StatusNotifierItem via DBus) - watcher + tray count MVP
- [ ] Audio service (Pipewire) + volume OSD
- [ ] Notification indicator + notification popup UI

### Hardware and networking

- [ ] Battery service (UPower via DBus)
- [ ] Power profiles (power-profiles-daemon via DBus)
- [ ] Brightness control + OSD
- [ ] Network service (NetworkManager via DBus)
- [ ] Bluetooth service (Bluez via DBus)
- [ ] System stats (CPU, RAM, temperature)

### Desktop shell

- [ ] Control center panel
- [ ] Keyboard layout switching
- [ ] PipeWire audio spectrum
- [ ] Clipboard manager
- [ ] Host/distro detection
- [ ] Application launcher / search
- [ ] Lock screen (ext-session-lock-v1)
- [ ] Idle inhibitor (prevent sleep)
- [ ] More compositors (Mango, Sway, Labwc)

### Theming and customization

- [ ] Palette generation (port python implementation to c++)
- [ ] Dark/light mode switching
- [ ] Settings panel
- [ ] I18n / translations
- [ ] Blur and advanced visual effects
- [ ] Night light (wlsunset)
- [ ] Sound effects

### Ecosystem

- [ ] Compositor integration (Hyprland)
- [ ] Plugin system
- [ ] Desktop widgets
- [ ] Update checker
- [ ] Calendar integration
- [ ] Geolocation (weather)

### Controls (`src/ui/controls/`)

- [ ] Toggle
- [ ] Button
- [ ] IconButton
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

### Widgets

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

### Desktop Widgets

- [ ] Clock
- [ ] Media player
- [ ] System stats
- [ ] Audio visualizer
- [ ] Weather
