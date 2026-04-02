Noctalia
===

## Stack
**libwayland-client** + **wayland-scanner** <- codegen from xml
**wlr-layer-shell** <- surfaces / layers
**xdg-output-unstable-v1** <- multi-monitor
**ext-session-lock-v1** <- lockscreen
**wp-cursor-shape** <- cursor handling (pointing etc)
**cairo** <- drawing
**pango** <- font stuff (RTL etc)
**sdbus-c++** <- dbus control
**libpipewire** <- audio
**inotify** <- config files etc
**toml++** or **glaze** <- config format (toml or json)

## Avoid

## UI

## Build

```sh
cmake -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build
```