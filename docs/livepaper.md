# Live Paper (projectM / Milkdrop visualizer wallpaper)

The optional **live paper** feature renders a libprojectM (Milkdrop)
audio visualizer as the desktop wallpaper and lock-screen background. It
was ported from the Qt/QML `livepaper-v5` branch to the pure C++20
Wayland + EGL/GLES v5 stack.

## Architecture

| Piece | File |
|-------|------|
| Visualizer renderer (drives one libprojectM instance into an FBO texture) | `src/render/visualizer/projectm_renderer.{h,cpp}` |
| Audio source (raw PCM tap, sibling of the spectrum tap) | `src/pipewire/pipewire_pcm_tap.{h,cpp}` |
| Preset scanning / rotation | visualizer service |
| Desktop wallpaper integration | `src/shell/wallpaper/wallpaper.cpp` |
| Lock-screen integration | `src/shell/lockscreen/lock_surface.cpp`, `lock_screen.cpp` |
| Shared EGL context | `src/render/gl_shared_context.cpp` |

The visualizer renders into a private FBO/texture that lives in the root
EGL share group, so the wallpaper and lock surfaces sample it directly
with no extra blits. `ProjectMRenderer::renderFrame()` makes the root
surfaceless context current, renders, then restores the caller's
context.

## Critical: the shared GL context must be GLES3, not GLES2

`GlSharedContext` requests `EGL_CONTEXT_CLIENT_VERSION = 3`
(`src/render/gl_shared_context.cpp`). **Do not lower this to 2.**

libprojectM 4.x renders through Vertex Array Objects, which are not core
in GLES2. Under a GLES2 context libprojectM's VAO / element-buffer
binding silently no-ops; Mesa then interprets libprojectM's VBO index
*offset* as a client-side pointer and `memcpy`s from a garbage address,
crashing deterministically on the first frame:

```
__memcpy_avx_unaligned_erms
tc_draw_user_indices_single        (Mesa glthread)
_mesa_DrawElementsBaseVertex
libprojectM::MilkdropPreset::FinalComposite::Draw
ProjectMRenderer::renderFrame
Wallpaper::onVisualizerTick
```

GLES3 is a strict superset of GLES2, so the ES2-targeted per-surface
render backends in the same share group (`gles_render_backend.cpp`) are
unaffected and intentionally remain ES2.

The original Qt `livepaper-v5` did not hit this because Qt's context
supported VAOs.

## Live-texture invalidation

The visualizer renders into a fixed GL texture *name* whose contents
change every tick but whose id never does. `WallpaperNode::setSources()`
dedups on id, so each visualizer tick must explicitly mark the node
paint-dirty (`Wallpaper::onVisualizerTick`) and the lock surface must
call `LockSurface::invalidateLivePaper()`; otherwise the surface freezes
on the first frame.

## Runtime configuration

Behaviour lives in the freeform `settings.wallpaper.live_paper` TOML
table (`enabled`, `fps`, mesh size, darken, audio source, preset
interval, …). See `example.toml`.

IPC handlers: `livepaper-next`, `livepaper-toggle`, `livepaper-enable`,
`livepaper-disable`.

## Nix / home-manager

The flake exposes a filtered presets pack as its own output:

```
nix build .#presets
```

`nix/filter-presets.py` drops `.milk` presets that paint excessively
bright frames or rapid strobes.

home-manager options (`programs.noctalia.wallpaper.live_paper`):

- **`defaultPresets`** — symlink the bundled, filtered presets pack into
  `$XDG_DATA_HOME/waylivepaper/presets`. Defaults to **`true` whenever
  `settings.wallpaper.live_paper.enabled` is set**, so enabling the
  visualizer is a single switch. Set `false` to manage presets yourself.
- **`presetsSource`** — directory to symlink instead of the bundled
  pack. Defaults to the flake's filtered `presets-cream-of-the-crop`.

So a consumer only needs:

```nix
programs.noctalia = {
  enable = true;
  systemd.enable = true;
  settings.wallpaper.live_paper = { enabled = true; fps = 30; };
};
```

## Deployment note

The systemd user service runs noctalia from a pinned nix store path
(the consumer's flake input). After pulling a new noctalia commit the
input must be bumped and `home-manager switch` re-run for the running
service to pick it up — restarting the service alone keeps the old
pinned binary.
