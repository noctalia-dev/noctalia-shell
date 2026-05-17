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

## Critical: load presets with the shared context current

Every `projectm_*` call that touches GL **must** run with the shared
surfaceless root context current — `initialize()` (`projectm_create`),
`renderFrame()` (`projectm_opengl_render_frame`), **and `loadPreset()`
(`projectm_load_preset_file`)**. `loadPreset()` originally omitted the
`makeCurrentSaved()` / `restore()` guard, which caused a deterministic
first-frame crash:

```
__memcpy_avx_unaligned_erms          <- driver reads indices from NULL
tc_draw_user_indices_single / iris_emit_index_buffer
_mesa_DrawElementsBaseVertex
libprojectM::MilkdropPreset::FinalComposite::Draw   (glDrawElements ..., nullptr)
ProjectMRenderer::renderFrame
Wallpaper::onVisualizerTick
```

Why: libprojectM builds each preset's GL objects **synchronously**
inside `projectm_load_preset_file()` — `FinalComposite`'s VAO and its
element buffer (`RenderItem::Init` → `InitVertexAttrib`). **VAOs are
container objects and are not shared across an EGL share group.** If the
preset is loaded with the caller's context (a surface backend, or none)
current, the VAO is created there; when `renderFrame()` later binds that
VAO id in the root context it is invalid, no `GL_ELEMENT_ARRAY_BUFFER`
is bound, and libprojectM's
`glDrawElements(GL_TRIANGLES, n, GL_UNSIGNED_INT, nullptr)` makes the
driver read indices from offset 0 of no buffer → NULL deref.

The Qt `livepaper-v5` prototype was unaffected because it used a single
consistent GL context for both preset loading and rendering.

Rule of thumb: **any future `projectm_*` call that allocates or touches
GL objects must be wrapped in the same make-current/restore dance.** The
CPU-only setters (`projectm_set_window_size` / `_mesa_size` / `_fps` /
`_preset_locked`, `projectm_pcm_add_float`) do not need it.

### Non-fixes (historical)

The `EGL_CONTEXT_CLIENT_VERSION = 3` request in `gl_shared_context.cpp`
and the per-frame `glFinish()` in `renderFrame()` were dead-ends from
debugging this crash, kept only as harmless defence:

- An EGL probe showed Mesa returns a 3.2 context with working VAOs even
  for an `EGL_CONTEXT_CLIENT_VERSION = 2` request, so the GLES2/3
  distinction never mattered here (still, requesting 3 is the portable
  thing for libprojectM and the ES2 surface backends are unaffected).
- The crash reproduced identically with Mesa glthread disabled
  (`MESA_GLTHREAD=false`), so it was never an async-marshalling race;
  `glFinish` could likely be relaxed to `glFlush` or removed with
  separate testing.

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
