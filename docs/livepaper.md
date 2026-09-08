# Live Paper (projectM / Milkdrop visualizer wallpaper)

The optional **live paper** feature renders a libprojectM (Milkdrop)
audio visualizer as the desktop wallpaper and lock-screen background. It
was ported from the Qt/QML `livepaper-v5` branch to the pure C++20
Wayland + EGL/GLES v5 stack.

## Architecture

| Piece | File |
|-------|------|
| Visualizer renderer (drives one libprojectM instance into a shared texture) | `src/render/visualizer/projectm_renderer.{h,cpp}` |
| Audio source (raw PCM tap, sibling of the spectrum tap) | `src/pipewire/pipewire_pcm_tap.{h,cpp}` |
| Preset scanning / rotation | visualizer service |
| Desktop wallpaper integration | `src/shell/wallpaper/wallpaper.cpp` |
| Lock-screen integration | `src/shell/lockscreen/lock_surface.cpp`, `lock_screen.cpp` |
| Shared EGL context | `src/render/gl_shared_context.cpp` |

`ProjectMRenderer::renderFrame()` makes the root context current with a
private hidden Wayland window surface, drives one libprojectM frame,
copies the result into a texture, and restores the caller's context. The
wallpaper / lock surfaces (each a different context in the share group)
sample that texture through an **EGLImage** — see the two sections below
for why neither a plain shared texture name nor a private FBO works.

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

## Critical: libprojectM composites to framebuffer 0, not your FBO

After the first-frame crash was fixed the wallpaper still rendered
**black**. Root cause: libprojectM 4.1.x `ProjectM::RenderFrame()` ends
with

```cpp
// ToDo: Allow external apps to provide a custom target framebuffer.
glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
m_textureCopier->Draw(m_activePreset->OutputTexture(), false, false);
```

i.e. it **ignores any externally bound FBO** and blits its final image
to **draw framebuffer 0**. With the producer on a *surfaceless* context,
framebuffer 0 is nowhere, so the visualizer's output was discarded and
our texture kept its cleared (all-zero) content.

The producer therefore needs a real default framebuffer. The Wayland EGL
platform exposes **no pbuffer configs** (probed: 180 window configs, 0
pbuffer), so the only option is a window surface. `createFbo()` makes a
private `wl_surface` that is **never assigned a role nor committed** (the
compositor never shows it), wraps it in a `wl_egl_window` + EGLSurface,
and `renderFrame()` makes the root context current *with* that surface.
libprojectM's hard-coded FBO-0 composite then lands in its back buffer,
which `glCopyTexSubImage2D` pulls into `m_textureName`. We never
`eglSwapBuffers` — the surface is only ever read back.

## Critical: cross-context sampling needs an EGLImage

An EGL share group shares object *names*, but on Mesa/iris a texture
whose contents were written in one context (here: the surfaceless-ish
producer) is **not reliably sampleable from another** (the per-output
wallpaper backend / lock surface contexts). A raw shared texture name
sampled black.

Fix: `createFbo()` wraps `m_textureName` in an `EGLImageKHR`
(`eglCreateImageKHR`, `EGL_GL_TEXTURE_2D_KHR`). Each consuming backend
imports it once as an alias texture
(`glEGLImageTargetTexture2DOES`, cached in
`GlesRenderBackend::importLiveImage`) and samples that. The producer's
per-frame `glCopyTexSubImage2D` writes the EGLImage's storage, so the
alias updates with no re-import. `WallpaperNode::liveImage()` carries the
`EGLImageKHR` (as `void*`) through the scene graph;
`render_context.cpp`'s `Wallpaper` case imports it and uses it for both
wallpaper sources (libprojectM cross-fades presets internally, so no
node-level transition is needed).

## Live-texture invalidation

The visualizer renders into a fixed GL texture *name* whose contents
change every tick but whose id never does. `WallpaperNode::setSources()`
dedups on id, so each visualizer tick must explicitly mark the node
paint-dirty (`Wallpaper::onVisualizerTick`) and the lock surface must
call `LockSurface::invalidateLivePaper()`; otherwise the surface freezes
on the first frame.

## Audio source

The visualizer's audio comes from `PipeWirePcmTap`, a raw-PCM capture
sibling of the bar's spectrum analyser. In its default *follow* mode
(empty `audio_source`) it mirrors the bar's audio-visualizer widget:

- While `PipeWireSpectrum` reports audio (the widget is visible) the tap
  captures the very node the spectrum analyses — normally the default
  sink's monitor — so the visualizer reacts to the same sound the widget
  shows.
- Once the spectrum goes idle (~1 s of silence, widget hidden) the tap
  has nothing to tap. **By default it stays unbound and the visualizer
  runs silent** until playback resumes.

### Mic fallback (privacy-relevant; opt-in)

Set `allow_mic_fallback = true` under `[wallpaper.live_paper]` to extend
follow mode with the prototype's original behaviour: when no audio is
playing, the tap falls back to the **default source (microphone)** so
the visualizer keeps reacting to ambient sound. The opt-in shape exists
because the fallback stream is intentionally **not**
`PW_KEY_NODE_PASSIVE` — it activates the microphone whenever follow mode
goes idle, which on a system without an xdg-desktop-portal mic gate is
not otherwise obvious to the user. The stream is visible in
`pavucontrol` / `wpctl status` as **"Noctalia LivePaper"**.

Sink-monitor taps stay passive so they never wake an idle sink.

The tap registers a `PipeWireSpectrum` listener while running, which
keeps the silence detection alive even when no audio-visualizer widget
is on the bar.

Source (mic / line-in) captures additionally run through an automatic
gain control — a peak envelope with fast attack and slow release feeding
a capped makeup gain — so quiet ambient sound still drives libprojectM's
beat/FFT analysis. Sink-monitor captures keep their native dynamics
(they already arrive at program level). See the `kAgc*` constants in
`pipewire_pcm_tap.cpp`.

`audio_source` set to an explicit PipeWire node name bypasses follow
mode and the mic-fallback gate entirely (the user named the node).

A subtlety in the renderer: `projectm_pcm_add_float`'s `count` argument
is **samples per channel** (the frame count), not the interleaved float
count — feeding `frames * channels` makes libprojectM ingest a frame of
stale ring data for every real one and the visualizer barely tracks the
music.

## Build-time gate

The feature is **opt-in at compile time** via the meson `livepaper` feature
option (default: `auto`). With `auto` the feature is enabled iff libprojectM 4
is found on the `pkg-config` path **and** actually links; otherwise the build
drops the feature (meson prints which). To force-enable (and fail the configure
when libprojectM is missing or unusable) use `-Dlivepaper=enabled`; to skip it
entirely even if libprojectM is installed use `-Dlivepaper=disabled`.

The link probe exists because a *found* libprojectM is not necessarily a usable
one: upstream's `projectM-4.pc` emits `-l:projectM-4`, an exact-filename flag
naming a file that does not exist (`libprojectM-4.so` is the real library), so
a bare `dependency()` check would pass and the final link would then fail.
Whether the library was built for **GLES** rather than desktop GL is *not*
detectable at configure time — that mismatch links cleanly and surfaces at
runtime instead, where `ProjectMRenderer::initialize()` fails and
`livepaper::rendererReady()` stays false. See [PACKAGING.md](../PACKAGING.md).

When the feature is compiled out, a stub TU (`livepaper_stub.cpp`) provides
empty implementations of `ProjectMRenderer`, `VisualizerService`, and
`PipeWirePcmTap` so the wallpaper / lock-screen integration code (which holds
non-owning pointers and already null-checks) continues to link and degrade to
the static-wallpaper-only behaviour.

## Hardware fallback (GLES2)

libprojectM 4.x relies on Vertex Array Objects, which are core in **GLES3**
and only an extension in GLES2. `GlSharedContext` therefore requests
`EGL_CONTEXT_CLIENT_VERSION = 3` and remembers which version it actually got
(`clientVersion()`). On hardware where GLES3 context creation fails (older
Adreno 3xx/4xx, older Mali-T, some legacy NVIDIA Wayland EGL) the shared
context falls back to GLES2 and the visualizer simply refuses to initialize —
the rest of the shell runs normally with the static wallpaper path. The
visualizer is opt-in and off by default, so users on legacy GPUs do not need
to do anything.

## Session-lock safety

While the session is locked the visualizer pins the currently-running preset
(`VisualizerService::setSessionLocked(true)`, wired from
`LockScreen::setSessionHooks`). The lock surface shares one libprojectM
instance with the wallpaper; a hypothetical SIGSEGV inside libprojectM while
loading a preset would terminate the shell, which terminates the
`ext-session-lock-v1` client, which most compositors interpret as a forced
unlock without authentication. Holding the preset constant for the duration
of the lock keeps the failure surface to "the wallpaper-time preset" — by
that point the user has already authenticated past it once.

## Runtime configuration

Behaviour lives in the freeform `settings.wallpaper.live_paper` TOML
table (`enabled`, `fps`, mesh size, render size, darken, audio source,
preset interval, …). See `example.toml`.

`render_width` / `render_height` (default `1280x720`, clamped to
320..7680) set the working resolution of the offscreen framebuffer the
visualizer renders into. There is exactly one such framebuffer for the
whole shell — every output and the lock surface sample the same texture and
scale it with `wallpaper.fill_mode` — so it is a global sharpness-vs-fill-rate
knob, not a per-output mode. On a large or high-DPI output the 720p default
is a visible upscale; raise it towards that output's mode, and pick an aspect
ratio matching it so `fill_mode` does not crop. Changing it at runtime is
handled by `VisualizerService::applyConfigToRenderer()` →
`ProjectMRenderer::resize()`, which rebuilds the FBO, texture and EGLImage and
publishes a new image serial so every consumer's alias cache re-imports.

IPC handlers: `livepaper-next`, `livepaper-toggle`, `livepaper-enable`,
`livepaper-disable`.

## Nix / home-manager

The filtered presets pack lives in a separate flake,
`presets-photosensitive-filtered` (a `flake.nix` input). It drops `.milk`
presets that paint excessively bright frames or rapid strobes, and exposes
the result as its `default` package — build it directly with:

```
nix build <presets-photosensitive-filtered-flake>
```

home-manager options (`programs.noctalia.wallpaper.live_paper`):

- **`defaultPresets`** — symlink the bundled, filtered presets pack into
  `$XDG_DATA_HOME/waylivepaper/presets`. Defaults to **`true` whenever
  `settings.wallpaper.live_paper.enabled` is set**, so enabling the
  visualizer is a single switch. Set `false` to manage presets yourself.
- **`presetsSource`** — directory to symlink instead of the bundled
  pack. Defaults to the filtered pack from the
  `presets-photosensitive-filtered` flake input.

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
