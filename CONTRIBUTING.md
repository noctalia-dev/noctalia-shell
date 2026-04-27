Contributing
===

This file collects contributor-facing details for Noctalia: design goals, stack notes, code style, source layout,
runtime asset behavior, and debugging helpers.

For dependencies and normal build commands, start with [README.md](README.md).

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
| Text | `cairo`, `pango`, `pangocairo`, `freetype`, `fontconfig` |
| Images | `Wuffs` (vendored), `nanosvg` (vendored), `stb_image_resize2` (vendored), `libwebp` |
| IPC | `sdbus-c++` |
| Audio | `libpipewire`, `dr_wav` (vendored) |
| Authentication | `PAM` |
| HTTP | `libcurl` |
| Config | `tomlplusplus` (vendored) |
| JSON | `nlohmann/json` (vendored) |
| Math expressions | `tinyexpr` (vendored) |
| Scripting | `Luau` (vendored) |
| Theme generation | Material Color Utilities (vendored) |

## Runtime Assets

`meson install` installs the binary and shipped assets separately using the normal prefix layout:

```text
/usr/local/bin/noctalia
/usr/local/share/noctalia/assets/...
```

With a different Meson `prefix`/`datadir`, the same structure is preserved under that prefix.

Noctalia needs the `assets/` tree at runtime. Copying only the bare `noctalia` binary is not enough.

Portable bundle layouts are also supported:

```text
bundle/
  noctalia
  assets/
```

```text
bundle/
  bin/noctalia
  share/noctalia/assets/
```

Runtime asset lookup order:

1. `NOCTALIA_ASSETS_DIR`
2. `assets/` next to the executable
3. `assets/` one level above the executable
4. install-style `../share/noctalia/assets` relative to the executable
5. the compiled install path from Meson (`<prefix>/<datadir>/noctalia/assets`)
6. the source-tree `assets/` directory as a development fallback

An asset root is only accepted if it contains the expected shipped files such as `emoji.json`, `fonts/tabler.ttf`,
`templates/builtin.toml`, and `translations/en.json`.

## Code Style

This project uses [clang-format](https://clang.llvm.org/docs/ClangFormat.html) for formatting. Run `just format`
before committing.

For editor integration, the repo includes a `.clangd` file. It points clangd at the Meson compilation database under
`build-release`, so run `just configure release` at least once if your editor uses clangd.

The repo also includes `lefthook.yml`. Run `lefthook install` to install the pre-commit hook; it runs `just format`
before commits and refreshes the git index for tracked formatting changes.

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

D-Bus wire-protocol string literals, such as `player["bus_name"]`, stay snake_case because they are wire names, not
C++ identifiers.

## Project Layout

```text
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
  stb/            Image resizing (vendored)
  tinyexpr/       Math expression evaluator (vendored)
  nlohmann/       JSON parser (vendored, header-only)
  dr_wav/         WAV decoder (vendored)
  luau/           Scripted widget runtime (vendored)
  material_color_utilities/ Material Design color generation (vendored)
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
