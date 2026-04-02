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

#### DBus (Required)
- [x] Implement `CloseNotification`
- [x] Implement `GetCapabilities`
- [x] Implement `GetServerInformation`
- [x] Emit `NotificationClosed`
- [x] Stub `ActionInvoked` signal

#### Lifecycle (Critical)
- [x] Handle timeout semantics (`-1` default, `0` persistent, `>0` custom)
- [x] Implement expiry system (timers / event loop)
- [x] Emit `NotificationClosed` with reason (expired / closed by call)

#### Core Behavior
- [x] Fully implement `replaces_id` (in-place update)
- [x] Always return final notification ID
- [ ] Prevent duplicate stacking when replacing

#### Capabilities (Minimal)
- [x] Return `body`
- [x] Return `actions` (stubbed)

#### Hints (Minimal Support)
- [x] Parse hints dictionary safely
- [x] Support `urgency`
- [x] Support `image-path` or `app_icon`
- [x] Ignore unknown hints

#### Data Model
- [x] Extend Notification with base fields (`app_name`, `summary`, `body`, `timeout`, `urgency`)
- [x] Extend Notification with optional fields (`icon`, `category`, `desktop_entry`)

#### Icons (Basic)
- [x] Store `app_icon` or `image-path`
- [ ] Display icon in UI layer

#### Stability
- [ ] Handle empty summary/body
- [ ] Handle invalid DBus input gracefully
- [x] Ensure no crashes on malformed hints

#### Later
- [ ] Notification closing/removal API polish
- [ ] Actions implementation (buttons + callbacks)

</details>

## Build

```sh
cmake -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build
```