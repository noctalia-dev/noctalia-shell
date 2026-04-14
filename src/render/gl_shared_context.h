#pragma once

#include <EGL/egl.h>

struct wl_display;

// Owns the EGLDisplay, the chosen EGLConfig, and a root surfaceless EGLContext
// that is the share parent for every other EGLContext in the shell
// (RenderContext, WallpaperRenderer instances, ...). By routing all contexts
// through this share group, GL textures uploaded in any of them are usable
// from every other context in the group — which lets LockSurface reuse
// wallpaper textures resident in VRAM without re-decoding.
class GlSharedContext {
public:
  GlSharedContext() = default;
  ~GlSharedContext();

  GlSharedContext(const GlSharedContext&) = delete;
  GlSharedContext& operator=(const GlSharedContext&) = delete;

  void initialize(wl_display* display);
  void cleanup();

  [[nodiscard]] EGLDisplay display() const noexcept { return m_display; }
  [[nodiscard]] EGLConfig config() const noexcept { return m_config; }
  [[nodiscard]] EGLContext rootContext() const noexcept { return m_rootContext; }

  // Bind the root context surfacelessly. Handy when a GL resource has to be
  // created before any rendering surface exists.
  void makeCurrentSurfaceless() const;

private:
  EGLDisplay m_display = EGL_NO_DISPLAY;
  EGLConfig m_config = nullptr;
  EGLContext m_rootContext = EGL_NO_CONTEXT;
};
