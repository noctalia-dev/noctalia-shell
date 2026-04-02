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

## To-Do
<details>
<summary>Notification</summary>

#### Core
- [x] Add `replaces_id` support (update existing notifications)
- [ ] Introduce basic event system (added / updated callbacks)
- [x] Switch storage to stable container (deque + ID lookup)

#### IPC
- [x] Design DBus interface skeleton (Notify method)
- [x] Integrate sdbus-c++ (initial stub)

#### Data Model
- [x] Extend Notification with base fields (app_name, summary, body, timeout, urgency)
- [ ] Extend Notification with optional fields (icon, category, hints)

#### Later
- [ ] Notification closing/removal
- [ ] Expiry handling (timeouts)
- [ ] Actions (buttons + callbacks)
- [ ] Full freedesktop.org compliance

</details>

## Build

```sh
cmake -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build
```