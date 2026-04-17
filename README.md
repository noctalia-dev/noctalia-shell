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
| Surfaces | `xdg-shell`, `zwlr-layer-shell-v1` |
| Multi-monitor | `zxdg-output-unstable-v1` |
| Active window metadata | `zwlr-foreign-toplevel-management-unstable-v1` |
| Workspaces | `ext-workspace-v1`, `dwl-ipc-unstable-v2` |
| Clipboard | `ext-data-control-v1`, `wlr-data-control-unstable-v1` |
| Activation | `xdg-activation-v1` |
| Lockscreen | `ext-session-lock-v1` |
| Idle | `ext-idle-notify-v1`, `idle-inhibit-unstable-v1` |
| Cursor | `wp-cursor-shape-v1` |
| Keyboard | `xkbcommon` |
| Rendering | `EGL`, `OpenGL ES 3`, `wayland-egl` |
| Text | `cairo`, `pango`, `pangocairo`, `freetype`, `harfbuzz`, `fontconfig` |
| Images | `Wuffs` (vendored), `nanosvg` (vendored), `libwebp` |
| IPC | `sdbus-c++` |
| Audio | `libpipewire` |
| Authentication | `PAM` |
| HTTP | `libcurl` |
| Config | `tomlplusplus` (vendored) |
| JSON | `nlohmann/json` (vendored) |
| Math expressions | `tinyexpr` (vendored) |

## Dependencies

### Fedora

```sh
sudo dnf install meson gcc-c++ just \
  wayland-devel wayland-protocols-devel \
  libEGL-devel mesa-libGLES-devel \
  freetype-devel harfbuzz-devel fontconfig-devel \
  cairo-devel pango-devel \
  libxkbcommon-devel \
  sdbus-cpp-devel pipewire-devel \
  pam-devel libcurl-devel libwebp-devel \
  libasan libubsan
```

### Arch

```sh
sudo pacman -S meson gcc just \
  wayland wayland-protocols \
  libglvnd freetype2 harfbuzz fontconfig \
  cairo pango \
  libxkbcommon \
  sdbus-cpp libpipewire \
  pam curl libwebp \
  gcc-libs
```

### Debian / Ubuntu

```sh
sudo apt install meson g++ just \
  libwayland-dev wayland-protocols \
  libegl-dev libgles-dev \
  libfreetype-dev libharfbuzz-dev libfontconfig-dev \
  libcairo2-dev libpango1.0-dev \
  libxkbcommon-dev \
  libsdbus-c++-dev libpipewire-0.3-dev \
  libpam0g-dev libcurl4-openssl-dev libwebp-dev \
  libasan8 libubsan1
```

Vendored (no system package needed): `Wuffs`, `nanosvg`, `tomlplusplus`, `tinyexpr`, `nlohmann/json`.

System packages required beyond the Wayland/GL stack: `libwebp` (VP8 lossy WebP; wuffs handles all other formats).

## Build

Requires [just](https://github.com/casey/just) and [meson](https://mesonbuild.com/).

```sh
# Debug (default) — builds in build-debug/
just configure
just build

# Optimized release (-march=native, LTO, gc-sections) — builds in build-release/
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
<summary>Manual Meson</summary>

```sh
meson setup build-debug                           # or: --buildtype=release -Db_lto=true
meson compile -C build-debug
./build-debug/noctalia
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
  main.cpp        Entry point
  app/            Application bootstrap, main loop
  auth/           PAM authentication (lockscreen)
  config/         Configuration and state persistence (TOML)
  core/           Logger, timer manager, shared utilities
  dbus/           DBus service implementations
  debug/          Debug service (runtime log toggling)
  idle/           Idle manager and inhibitor
  ipc/            IPC client/service (dev.noctalia.* commands)
  launcher/       Launcher providers (apps, emoji, math, usage)
  net/            HTTP client (libcurl)
  notification/   Notification manager
  pipewire/       PipeWire audio service and spectrum analyzer
  render/
    animation/    Animation manager and easing
    core/         EGL/GLES renderer, image decoders
    programs/     Shader programs per NodeType
    scene/        Scene graph nodes (Rect, Text, Image, Icon, InputArea, ...)
    text/         Cairo/Pango text rendering
  shell/
    bar/          Bar surface and instance
    clipboard/    Clipboard history panel
    control_center/ Control center panel and tabs
    launcher/     Application launcher panel
    lockscreen/   Session lockscreen surface
    notification/ Notification popup
    osd/          On-screen display (volume, brightness, ...)
    overview/     Workspace overview
    panel/        Panel base and manager
    session/      Session menu (logout, reboot, ...)
    tray/         System tray (StatusNotifierItem)
    wallpaper/    Wallpaper surface and instance
    widget/       Widget base and factory
    widgets/      Widget implementations
  system/         System monitor (CPU, RAM, temperature)
  time/           Time service and polling
  ui/
    controls/     Low-level UI building blocks (Button, Input, Label, Flex, ...)
  util/           Generic helpers (fuzzy matching, ...)
  wayland/        Wayland connection, seat, toplevels, clipboard, ...
    compositors/  Compositor-specific workspace backends (ext-workspace, sway, mango, dwl, ...)
third_party/
  tomlplusplus/   TOML parser (vendored)
  wuffs/          Raster image decoding (vendored)
  nanosvg/        SVG rasterization (vendored)
  tinyexpr/       Math expression evaluator (vendored)
  nlohmann/       JSON parser (vendored, header-only)
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

## Configuration

Noctalia reads `$XDG_CONFIG_HOME/noctalia/config.toml` or `~/.config/noctalia/config.toml`.
If no config file exists, it falls back to built-in defaults in code.

See [CONFIG.md](CONFIG.md) for the full configuration reference, including shell IPC command examples.
