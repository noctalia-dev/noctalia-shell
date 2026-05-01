#include "render/render_target.h"

#include "render/render_context.h"

#include <stdexcept>
#include <wayland-egl.h>

RenderTarget::~RenderTarget() { destroy(); }

void RenderTarget::create(wl_surface* surface, RenderContext& context) {
  m_wlSurface = surface;
  const auto* native = context.backend().glesNative();
  if (native == nullptr) {
    throw std::runtime_error("RenderTarget requires a GLES-native backend");
  }
  m_eglDisplay = native->display;
  m_eglConfig = native->config;
}

void RenderTarget::resize(std::uint32_t bufferWidth, std::uint32_t bufferHeight) {
  if (bufferWidth == 0 || bufferHeight == 0) {
    return;
  }

  m_bufferWidth = bufferWidth;
  m_bufferHeight = bufferHeight;

  if (m_window == nullptr) {
    m_window = wl_egl_window_create(m_wlSurface, static_cast<int>(bufferWidth), static_cast<int>(bufferHeight));
    if (m_window == nullptr) {
      return;
    }

    m_eglSurface =
        eglCreateWindowSurface(m_eglDisplay, m_eglConfig, reinterpret_cast<EGLNativeWindowType>(m_window), nullptr);
  } else {
    wl_egl_window_resize(m_window, static_cast<int>(bufferWidth), static_cast<int>(bufferHeight), 0, 0);
  }
}

void RenderTarget::destroy() {
  if (m_eglSurface != EGL_NO_SURFACE) {
    eglDestroySurface(m_eglDisplay, m_eglSurface);
    m_eglSurface = EGL_NO_SURFACE;
  }

  if (m_window != nullptr) {
    wl_egl_window_destroy(m_window);
    m_window = nullptr;
  }

  m_wlSurface = nullptr;
  m_bufferWidth = 0;
  m_bufferHeight = 0;
  m_logicalWidth = 0;
  m_logicalHeight = 0;
}
