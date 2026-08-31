#pragma once

#include "render/core/texture_handle.h"

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

class GlSharedContext;
class PipeWirePcmTap;
struct wl_compositor;

// Drives a single libprojectM (Milkdrop) instance and exposes its latest frame
// as a GL texture handle. The texture lives in the root EGL share group, so
// any WallpaperRenderer / LockSurface in the same group can sample it without
// extra blits.
//
// The renderer takes the root surfaceless context current when rendering, then
// restores whatever context/surface was current on entry. Callers can safely
// invoke renderFrame() from the main loop without worrying about clobbering a
// render target they had bound.
class ProjectMRenderer {
public:
  ProjectMRenderer();
  ~ProjectMRenderer();

  ProjectMRenderer(const ProjectMRenderer&) = delete;
  ProjectMRenderer& operator=(const ProjectMRenderer&) = delete;

  // Bind to the shared GL group and create the offscreen FBO + texture. Must
  // be called exactly once before renderFrame(). pcmTap may be null at init
  // time — set it later with setPcmTap(); the renderer simply feeds silence
  // until a tap is attached.
  // compositor is used to create a hidden, never-committed wl_surface that
  // backs the producer's EGL window surface. libprojectM 4.1.x hard-codes its
  // final composite to draw framebuffer 0, and the Wayland EGL platform has no
  // pbuffer configs, so a (never-shown) window surface is the only way to give
  // libprojectM a real default framebuffer.
  bool initialize(GlSharedContext& shared, wl_compositor* compositor, std::uint32_t width, std::uint32_t height);
  void shutdown();

  // Texture size. resize() recreates the FBO/texture; cheap, but the
  // libprojectM internal mesh is also resized to the new dimensions.
  void resize(std::uint32_t width, std::uint32_t height);
  [[nodiscard]] std::uint32_t width() const noexcept { return m_width; }
  [[nodiscard]] std::uint32_t height() const noexcept { return m_height; }
  [[nodiscard]] TextureHandle textureHandle() const noexcept;

  // EGLImageKHR (opaque void*) wrapping the offscreen texture. The visualizer
  // renders in the shared root context; consumers in other share-group
  // contexts (the wallpaper/lock surfaces) cannot reliably sample the raw
  // texture name on Mesa, so they import this image into their own context
  // instead. Null until initialize() succeeds.
  [[nodiscard]] void* eglImage() const noexcept { return m_eglImage; }

  // Monotonic counter, bumped every time a new EGLImage is published (once at
  // initialize(), then on every resize()). Consumers that cache an imported
  // alias texture keyed on the image pointer MUST fold this into their key:
  // destroying an EGLImage and creating the next one can legitimately hand
  // back the very same address, so the pointer alone cannot tell "same image"
  // apart from "different image, recycled address".
  [[nodiscard]] std::uint64_t eglImageSerial() const noexcept { return m_eglImageSerial; }

  // Knobs from [wallpaper.live_paper] in TOML. Safe to call after init.
  void setMeshSize(int meshW, int meshH);
  void setFps(int fps);

  // Load a specific Milkdrop preset (.milk / .prjm) with a soft cross-fade.
  // Empty path is silently ignored — the existing preset keeps running.
  void loadPreset(const std::string& path);

  // Set the directories libprojectM scans for textures referenced by rand00..15
  // samplers. Must be called before loading any preset that uses rand-samplers.
  // Calling with an empty vector clears the search paths.
  void setTextureSearchPaths(const std::vector<std::string>& paths);

  // Audio source. Renderer holds a non-owning pointer; null = silent.
  void setPcmTap(PipeWirePcmTap* tap) noexcept { m_pcmTap = tap; }

  // Drive one frame of the visualizer. Pulls whatever PCM is buffered in the
  // tap, feeds it to libprojectM, then renders into the internal FBO. Safe
  // to call when libprojectM is not initialised — returns silently.
  void renderFrame();

private:
  struct GlState; // forward — defined in .cpp to keep EGL/GL types out of the header
  void makeCurrentSaved(GlState& saved);
  static void restore(const GlState& saved);
  void destroyFbo();
  bool createFbo(std::uint32_t width, std::uint32_t height);
  void pumpPcm();

  GlSharedContext* m_shared = nullptr;
  void* m_projectm = nullptr; // projectm_handle — opaque to keep header clean

  wl_compositor* m_compositor = nullptr;

  std::uint32_t m_width = 0;
  std::uint32_t m_height = 0;
  std::uint32_t m_textureName = 0;
  // Hidden producer drawable. libprojectM 4.1.x composites to draw framebuffer
  // 0, so the root context is made current *with* this window surface (FBO 0
  // == its back buffer) and renderFrame() copies it into m_textureName. The
  // wl_surface is never assigned a role nor committed, so it is never shown.
  // All void* to keep wayland/EGL types out of the header.
  void* m_wlSurface = nullptr;    // wl_surface*
  void* m_wlEglWindow = nullptr;  // wl_egl_window*
  void* m_eglSurface = nullptr;   // EGLSurface
  void* m_eglImage = nullptr; // EGLImageKHR aliasing m_textureName for cross-context sharing
  std::uint64_t m_eglImageSerial = 0; // bumped per published image; see eglImageSerial()

  int m_meshW = 24;
  int m_meshH = 18;
  int m_fps = 30;

  PipeWirePcmTap* m_pcmTap = nullptr;
  std::vector<float> m_pcmScratch; // pre-sized to avoid per-frame allocs
};
