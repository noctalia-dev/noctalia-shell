#pragma once

#include <EGL/egl.h>
#include <cstdint>

struct wl_egl_window;
struct wl_surface;

class RenderBackend;
class RenderContext;

class RenderTarget {
public:
  RenderTarget() = default;
  ~RenderTarget();

  RenderTarget(const RenderTarget&) = delete;
  RenderTarget& operator=(const RenderTarget&) = delete;

  void create(wl_surface* surface, RenderContext& context);
  void create(wl_surface* surface, RenderBackend& backend);
  void resize(std::uint32_t bufferWidth, std::uint32_t bufferHeight);
  void destroy();

  [[nodiscard]] EGLSurface eglSurface() const noexcept { return m_eglSurface; }
  [[nodiscard]] std::uint32_t bufferWidth() const noexcept { return m_bufferWidth; }
  [[nodiscard]] std::uint32_t bufferHeight() const noexcept { return m_bufferHeight; }
  [[nodiscard]] std::uint32_t logicalWidth() const noexcept { return m_logicalWidth; }
  [[nodiscard]] std::uint32_t logicalHeight() const noexcept { return m_logicalHeight; }
  [[nodiscard]] bool isReady() const noexcept { return m_eglSurface != EGL_NO_SURFACE; }

  void setLogicalSize(std::uint32_t w, std::uint32_t h) noexcept {
    m_logicalWidth = w;
    m_logicalHeight = h;
  }

private:
  wl_surface* m_wlSurface = nullptr;
  wl_egl_window* m_window = nullptr;
  EGLDisplay m_eglDisplay = EGL_NO_DISPLAY;
  EGLConfig m_eglConfig = nullptr;
  EGLSurface m_eglSurface = EGL_NO_SURFACE;
  std::uint32_t m_bufferWidth = 0;
  std::uint32_t m_bufferHeight = 0;
  std::uint32_t m_logicalWidth = 0;
  std::uint32_t m_logicalHeight = 0;
};
