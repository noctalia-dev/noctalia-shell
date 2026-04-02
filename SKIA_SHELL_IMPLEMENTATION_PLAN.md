# Skia Shell Implementation Plan

## Goal
Build a Wayland shell and bar runtime that keeps Qt's memory footprint out of the process while preserving the features that matter for Noctalia:

- multi-monitor layer-shell surfaces
- smooth animations
- shader-capable rendering
- room for notifications, OSDs, dashboards, and lock surfaces

The rendering target is `Skia + OpenGL` for the first pass. Wayland integration stays direct through `libwayland-client` and generated protocol bindings.

## Principles
- Get a real bar surface on screen early.
- Keep the scene graph tiny and domain-specific.
- Prefer surface-level invalidation first; defer region-level optimization.
- Defer blur and advanced effects until frame scheduling is stable.
- Keep service integrations isolated behind small adapters.

## Initial Stack
- `libwayland-client`
- `wayland-protocols`
- `wayland-scanner`
- `zwlr-layer-shell-v1`
- `zxdg-output-manager-v1`
- `Skia`
- `fmt`
- `spdlog`
- `sdbus-c++`

## Repo Layout
```text
src/
  app/
  dbus/
  notification/
  shell/
  wayland/
  render/
  scene/
  ui/
  services/
```

## Milestones

### Phase 0: Foundation
- Add build plumbing for Wayland and protocol code generation.
- Introduce shell-specific modules without disrupting the notification path.
- Keep `Application` as the single bootstrap point.

Exit criteria:
- Project configures with Wayland dependencies.
- Shell modules compile even if they only log and discover globals.

### Phase 1: Bare Layer-Shell Surface
- Bind `wl_compositor`, `wl_seat`, `wl_output`, `zwlr_layer_shell_v1`, and `zxdg_output_manager_v1`.
- Create one top-anchored layer-shell bar surface.
- Handle `configure`, `ack_configure`, size, and frame callbacks.
- Target one monitor first.

Exit criteria:
- A blank bar surface appears reliably on one output.

### Phase 2: Skia Rendering
- Create a GPU-backed Skia render target per surface.
- Render background, rounded rects, and text.
- Keep redraw logic tied to Wayland frame callbacks.

Exit criteria:
- A Skia-rendered bar background and text appear on screen.

### Phase 3: Minimal Scene Graph
Start with:
- `Node`
- `ContainerNode`
- `RectNode`
- `TextNode`

Each node should support:
- bounds
- visibility
- opacity
- transform
- dirty state
- paint traversal

Exit criteria:
- The bar is rendered from a retained tree rather than raw draw calls.

### Phase 4: Invalidation and Animation
- Add per-surface invalidation.
- Add property animations for opacity, position, and size.
- Only redraw while dirty or while animations are active.

Exit criteria:
- Idle surfaces stay idle; animated surfaces redraw smoothly.

### Phase 5: Multi-Monitor
- Create one `BarSurface` per output.
- Handle output add/remove/change.
- Use `xdg-output` metadata for stable naming.

Exit criteria:
- Multiple monitors each get an independently managed bar.

### Phase 6: Services and Components
Initial components:
- workspaces
- clock
- notification indicator
- media status
- audio status

Initial services:
- notifications
- MPRIS
- battery / power
- audio

Exit criteria:
- The bar is data-driven by internal models, not protocol objects.

## Initial Class Layout

### `src/app/`
- `Application`
  - Owns shell bootstrap, notification service, and lifecycle coordination.

### `src/shell/`
- `BarShell`
  - High-level shell runtime.
  - Coordinates Wayland connection and later the bar surfaces.

### `src/wayland/`
- `WaylandConnection`
  - Connects to the display.
  - Binds registry globals.
  - Tracks outputs and core shell interfaces.
- `Output`
  - Output identity and geometry metadata.
- `LayerSurface`
  - One layer-shell surface and its configure/frame lifecycle.

### `src/render/`
- `Renderer`
  - Abstract renderer entry point.
- `SkiaRenderer`
  - Skia/OpenGL implementation.

### `src/scene/`
- `Node`
- `ContainerNode`
- `RectNode`
- `TextNode`
- `AnimationController`

### `src/ui/`
- `BarView`
  - Builds the scene subtree for one bar.
- `WorkspaceStrip`
- `ClockView`

### `src/services/`
- `NotificationModel`
- `MprisModel`
- `AudioModel`

## First Four Execution Steps
1. Land Wayland build plumbing and protocol generation.
2. Build a `WaylandConnection` that discovers required globals and outputs.
3. Split a `BarShell` runtime out of `Application`.
4. Add a `LayerSurface` that can open a blank bar on one output.

## Phase 1 Task Checklist
- [ ] Add `FindPkgConfig`-based Wayland dependency wiring to CMake.
- [ ] Generate client protocol headers/code for:
  - [ ] `wlr-layer-shell-unstable-v1`
  - [ ] `xdg-output-unstable-v1`
- [ ] Add `src/shell/BarShell.*`
- [ ] Add `src/wayland/WaylandConnection.*`
- [ ] Bind required globals from the registry.
- [ ] Track available outputs.
- [ ] Print a startup summary of discovered globals and outputs.
- [ ] Prepare the app bootstrap so shell startup does not block future DBus work.

## Immediate Follow-Up After Phase 1
- Add `LayerSurface`.
- Get one blank bar surface on screen.
- Add configure and frame handling before introducing Skia.
