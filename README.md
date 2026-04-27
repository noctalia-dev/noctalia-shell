Noctalia
===

A lightweight Wayland shell and bar built directly on Wayland + OpenGL ES, with no Qt or GTK dependency.

Noctalia is in early development. Expect breaking configuration and behavior changes while the project is still taking shape.

## Dependencies

### Fedora

```sh
sudo dnf install meson gcc-c++ just \
  wayland-devel wayland-protocols-devel \
  libEGL-devel mesa-libGLES-devel \
  freetype-devel fontconfig-devel \
  cairo-devel pango-devel \
  libxkbcommon-devel \
  sdbus-cpp-devel pipewire-devel \
  pam-devel libcurl-devel libwebp-devel
```

### Arch

```sh
sudo pacman -S meson gcc just \
  wayland wayland-protocols \
  libglvnd freetype2 fontconfig \
  cairo pango \
  libxkbcommon \
  sdbus-cpp libpipewire \
  pam curl libwebp
```

### Debian / Ubuntu

```sh
sudo apt install meson g++ just \
  libwayland-dev wayland-protocols \
  libegl-dev libgles-dev \
  libfreetype-dev libfontconfig-dev \
  libcairo2-dev libpango1.0-dev \
  libxkbcommon-dev \
  libsdbus-c++-dev libpipewire-0.3-dev \
  libpam0g-dev libcurl4-openssl-dev libwebp-dev
```

Vendored dependencies, with no system package needed: `Wuffs`, `nanosvg`, `tomlplusplus`, `tinyexpr`,
`nlohmann/json`, `Luau`, `dr_wav`, `stb_image_resize2`, and Material Color Utilities.

System packages required beyond the Wayland/GL stack: `libwebp` handles WebP decoding and thumbnail encoding. Wuffs
handles the other supported raster image formats.

Sanitizer runtime packages are only needed for ASan/UBSan builds configured with `just configure asan`.

## Build

Requires [just](https://github.com/casey/just) and [meson](https://mesonbuild.com/).

```sh
# Debug build in build-debug/
just configure
just build
just run

# Optimized release build in build-release/
just configure release
just build release
just run release

# Clean rebuild
just rebuild
just rebuild release
```

## Installation

After building, install with `just`:

```sh
sudo just install release
```

Use `sudo just install` instead if you configured the default debug build.

Meson installs the binary and shipped assets using the normal prefix layout:

```text
/usr/local/bin/noctalia
/usr/local/share/noctalia/assets/...
```

Noctalia needs the shipped `assets/` tree at runtime. Copying only the `noctalia` binary is not enough.

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

See [CONTRIBUTING.md](CONTRIBUTING.md#runtime-assets) for the full runtime asset lookup order.

## Configuration

Noctalia has two configuration layers:

- Declarative user config lives in `$XDG_CONFIG_HOME/noctalia/` or `~/.config/noctalia/`.
  Noctalia reads every `*.toml` file in that directory, sorted alphabetically, and deep-merges them into one config.
  A single `config.toml` is the simplest setup, but splitting config into files such as `bar.toml`, `theme.toml`,
  or `widgets.toml` is also supported.
- GUI-managed overrides live in `$XDG_STATE_HOME/noctalia/settings.toml` or
  `~/.local/state/noctalia/settings.toml`. This file is written by Noctalia itself for settings changed through the
  UI, IPC-backed controls, setup flows, and other runtime actions that need persistence.

Load order is built-in defaults first, then declarative config files, then `settings.toml`.
Because the state file is applied last, GUI overrides win over matching values in `config.toml`.

Use the declarative config directory for hand-authored, dotfile-managed configuration. Treat `settings.toml` as an
app-managed override layer: inspect or delete it when you want to understand or clear GUI changes, but do not rely on
it as the primary place for curated config. Keeping the override file outside `~/.config` also allows the GUI to save
changes when the config directory is read-only, such as on NixOS.

Both layers are watched for changes and hot-reloaded. If neither declarative config nor state overrides exist,
Noctalia falls back to built-in defaults in code.

A ready-to-use starting config with all defaults is at [example.toml](example.toml). See [CONFIG.md](CONFIG.md) for the
full configuration reference.

## Contributing

Developer notes, architecture overview, code style, project layout, and debugging commands live in
[CONTRIBUTING.md](CONTRIBUTING.md).
