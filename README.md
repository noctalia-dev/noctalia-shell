Noctalia
===

A lightweight Wayland shell and bar with no Qt or GTK dependency.

## Design Principles

- Direct Wayland + OpenGL ES only -- no toolkit overhead
- Minimal scene graph, domain-specific to shell UI
- Packaging should work across all major Linux distros: Arch, NixOS, Fedora, Gentoo, Debian, Void, OpenSuse

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

## Dependencies

### Fedora

```sh
sudo dnf install cmake gcc-c++ just \
  wayland-devel wayland-protocols-devel \
  libEGL-devel mesa-libGLES-devel \
  freetype-devel harfbuzz-devel fontconfig-devel \
  sdbus-cpp-devel \
  libasan libubsan
```

### Arch

```sh
sudo pacman -S cmake gcc just \
  wayland wayland-protocols \
  libglvnd freetype2 harfbuzz fontconfig \
  sdbus-cpp \
  gcc-libs
```

### Debian / Ubuntu

```sh
sudo apt install cmake g++ just \
  libwayland-dev wayland-protocols \
  libegl-dev libgles-dev \
  libfreetype-dev libharfbuzz-dev libfontconfig-dev \
  libsdbus-c++-dev \
  libasan8 libubsan1
```

Vendored (no system package needed): `msdfgen`, `stb`, `nanosvg`, `tomlplusplus`.

## Build

Requires [just](https://github.com/casey/just).

```sh
git submodule update --init --recursive

# Debug (default)
just configure
just build

# Optimized release (-O3, LTO, native)
just configure release
just build release

# Clean rebuild
just rebuild          # debug
just rebuild release  # release

# Run debug
just run

# Run release
just run release
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

### Naming Conventions

| | Convention | Example |
|---|---|---|
| Files | snake_case | `widget_factory.cpp` |
| Directories | snake_case | `shell/widgets/` |
| Types / Classes | PascalCase | `WidgetFactory` |
| Functions / Methods | camelCase | `createWidget()` |
| Variables / Parameters | camelCase | `busName` |
| Private members | m_camelCase | `m_changeCallback` |
| Macros / Enum values | SCREAMING_SNAKE_CASE | `MAX_SIZE` |

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
  shell/
    bar/         Bar surface and instance
    notification/ Notification popup
    panel/       Panel base and manager
    panels/      Panel implementations
    wallpaper/   Wallpaper surface and instance
    widget/      Widget base and factory
    widgets/     Widget implementations
  system/        System monitor (CPU, RAM, temperature)
  time/          Time service and polling
  ui/
    controls/    Low-level UI building blocks
    icons/       Icon registry
  wayland/       Wayland connection, layer-shell surfaces
third_party/
  msdfgen/       MSDF glyph generation (git submodule)
  tomlplusplus/  TOML parser (vendored)
  stb/           Image loading (vendored)
  nanosvg/       SVG rasterization (vendored)
```

## Debugging

All debug commands use the `dev.noctalia.Debug` D-Bus service, available at runtime.

```sh
# Enable verbose debug logs
gdbus call --session --dest dev.noctalia.Debug --object-path /dev/noctalia/Debug --method dev.noctalia.Debug.SetVerboseLogs true

# Disable verbose debug logs
gdbus call --session --dest dev.noctalia.Debug --object-path /dev/noctalia/Debug --method dev.noctalia.Debug.SetVerboseLogs false

# Check current verbose log state
gdbus call --session --dest dev.noctalia.Debug --object-path /dev/noctalia/Debug --method dev.noctalia.Debug.GetVerboseLogs

# Emit an internal notification (app_name, summary, body, timeout_ms, urgency 0-2)
gdbus call --session --dest dev.noctalia.Debug --object-path /dev/noctalia/Debug --method dev.noctalia.Debug.EmitInternalNotification "Noctalia" "Test" "Hello from debug" 5000 1
```

## Roadmap

### Bar completion and foundation

- [x] Volume OSD
- [x] Notification: history panel

### Hardware and networking

- [ ] Brightness control + OSD
- [ ] Network service (NetworkManager via DBus)
- [ ] Bluetooth service (Bluez via DBus)

### Desktop shell

- [ ] Application launcher / search
- [ ] Control center panel (Weather, Media, Audio vol., )
- [ ] Keyboard layout switching
- [ ] PipeWire audio spectrum
- [ ] Clipboard manager
- [x] Host/distro detection
- [~] Lock screen (ext-session-lock-v1) <- still needs polish 
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

- [ ] Geolocation (weather)
- [ ] Compositor integration (Hyprland)
- [ ] Desktop widgets
- [ ] Update checker
- [ ] Calendar integration
- [ ] Plugin system

### Controls (`src/ui/controls/`)

- [x] Scroll view
- [ ] List view
- [ ] Checkbox
- [x] Radio button
- [ ] Tab bar
- [ ] Grid view
- [ ] Context menu
- [ ] Color picker

### Widgets

- [~] Tray
- [ ] Network
- [ ] Bluetooth
- [ ] Brightness
- [ ] Media mini
- [ ] Microphone
- [ ] Power profile
- [ ] System monitor
- [ ] Active window
- [ ] Dock
- [ ] Keyboard layout
- [ ] Lock keys (Caps/Num)
- [ ] Dark mode button
- [ ] Night light button
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
