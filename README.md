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
  libxkbcommon-devel glib2-devel \
  sdbus-cpp-devel pipewire-devel \
  pam-devel polkit-devel libcurl-devel libwebp-devel librsvg2-devel
```

### Arch

```sh
sudo pacman -S meson gcc just \
  wayland wayland-protocols \
  libglvnd freetype2 fontconfig \
  cairo pango \
  libxkbcommon glib2 \
  sdbus-cpp libpipewire polkit \
  pam curl libwebp librsvg
```

### Debian / Ubuntu

```sh
sudo apt install meson g++ just \
  libwayland-dev wayland-protocols \
  libegl-dev libgles-dev \
  libfreetype-dev libfontconfig-dev \
  libcairo2-dev libpango1.0-dev \
  libxkbcommon-dev libglib2.0-dev \
  libsdbus-c++-dev libpipewire-0.3-dev \
  libpam0g-dev libpolkit-agent-1-dev libpolkit-gobject-1-dev \
  libcurl4-openssl-dev libwebp-dev librsvg2-dev
```

### AerynOS
```sh
sudo moss it meson g++ just \
  wayland-devel wayland-protocols-devel \
  mesa-libegl-devel mesa-libgl-devel \
  freetype-devel fontconfig-devel \
  cairo-devel pango-devel \
  libxkbcommon-devel glib2-devel \
  sdbus-cpp-devel pipewire-devel \
  linux-pam-devel polkit-devel curl-devel libwebp-devel librsvg-devel extra-cmake-modules
```

### VoidLinux
```sh
sudo xbps-install meson ninja pkg-config git \
  wayland-devel wayland-protocols libepoxy-devel \
  MesaLib-devel libglvnd-devel cairo-devel \
  pango-devel fontconfig-devel freetype-devel \
  harfbuzz-devel libxkbcommon-devel pipewire-devel \
  libcurl-devel pam-devel libwebp-devel \
  basu-devel libcurl-devel sdbus-c++-devel \
  polkit-devel  librsvg-devel
```

Vendored dependencies, with no system package needed: `Wuffs`, `tomlplusplus`, `tinyexpr`,
`nlohmann/json`, `Luau`, `dr_wav`, `fzy`, `stb_image_resize2`, and Material Color Utilities.

System packages required beyond the Wayland/GL stack: `libwebp` handles WebP decoding and thumbnail encoding. Wuffs
handles the other supported raster image formats.

Polkit agent support requires development files that provide the `polkit-agent-1` and `polkit-gobject-1` pkg-config
modules. Some distros ship these in the runtime `polkit` package, while split-package distros use names such as
`polkit-devel`, `polkit-dev`, or `libpolkit-agent-1-dev` / `libpolkit-gobject-1-dev`.

**Optional:** installing `jemalloc` (Fedora: `jemalloc-devel`, Arch: `jemalloc`, Debian/Ubuntu: `libjemalloc-dev`, Void: `jemalloc`)
reduces memory fragmentation in long-running sessions. When detected at build time it is used automatically.

Sanitizer runtime packages are only needed for ASan/UBSan builds configured with `just configure asan`.

## Building and install

Requires [just](https://github.com/casey/just) and [meson](https://mesonbuild.com/).

#### Release build
```sh
# Optimized release build in build-release/
just configure release
just build release

# After building, install
sudo just install release
```

#### Debug build
```sh
# Debug build in build-debug/ don't use debug unless you are debugging...
just configure
just build

# Test your local debug build with
just run
```

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

- Declarative user config lives in `$NOCTALIA_CONFIG_HOME/noctalia/`, `$XDG_CONFIG_HOME/noctalia/`, or
  `~/.config/noctalia/`.
  Noctalia reads every `*.toml` file in that directory, sorted alphabetically, and deep-merges them into one config.
  A single `config.toml` is the simplest setup, but splitting config into files such as `bar.toml`, `theme.toml`,
  or `widgets.toml` is also supported.
- GUI-managed overrides live in `$NOCTALIA_STATE_HOME/noctalia/settings.toml`,
  `$XDG_STATE_HOME/noctalia/settings.toml`, or `~/.local/state/noctalia/settings.toml`. This file is written by
  Noctalia itself for settings changed through the UI, IPC-backed controls, setup flows, and other runtime actions
  that need persistence.

`NOCTALIA_CONFIG_HOME` and `NOCTALIA_STATE_HOME` are Noctalia-specific overrides with the same "home root" semantics
as the XDG variables. For example, `NOCTALIA_CONFIG_HOME=/tmp/profile` loads config from
`/tmp/profile/noctalia/`. Prefer these variables over overriding `XDG_CONFIG_HOME` when launching Noctalia from a
session, because applications started through Noctalia's launcher inherit the shell environment.

Load order is built-in defaults first, then declarative config files, then `settings.toml`.
Because the state file is applied last, GUI overrides win over matching values in `config.toml`.

Use the declarative config directory for hand-authored, dotfile-managed configuration. Treat `settings.toml` as an
app-managed override layer: inspect or delete it when you want to understand or clear GUI changes, but do not rely on
it as the primary place for curated config. Keeping the override file outside `~/.config` also allows the GUI to save
changes when the config directory is read-only, such as on NixOS.

Both layers are watched for changes and hot-reloaded. If neither declarative config nor state overrides exist,
Noctalia falls back to built-in defaults in code.

A ready-to-use starting config with all defaults is at [example.toml](example.toml). The full configuration reference
lives in the [documentation site](https://docs.noctalia.dev/v5/).

## Contributing

Developer notes, architecture overview, code style, project layout, and debugging commands live in
[CONTRIBUTING.md](CONTRIBUTING.md).
