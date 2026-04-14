#include "render/wallpaper_renderer.h"

#include "render/gl_shared_context.h"

#include <stdexcept>

#include <GLES2/gl2.h>
#include <wayland-egl.h>

namespace {

  constexpr EGLint kContextAttributes[] = {
      EGL_CONTEXT_CLIENT_VERSION,
      2,
      EGL_NONE,
  };

} // namespace

WallpaperRenderer::WallpaperRenderer() = default;

WallpaperRenderer::~WallpaperRenderer() { cleanup(); }

void WallpaperRenderer::bind(GlSharedContext& shared, wl_surface* surface) {
  if (surface == nullptr) {
    throw std::runtime_error("wallpaper renderer requires a valid Wayland surface");
  }

  m_surface = surface;
  m_eglDisplay = shared.display();
  m_eglConfig = shared.config();

  m_eglContext = eglCreateContext(m_eglDisplay, m_eglConfig, shared.rootContext(), kContextAttributes);
  if (m_eglContext == EGL_NO_CONTEXT) {
    throw std::runtime_error("eglCreateContext failed");
  }
}

void WallpaperRenderer::makeCurrent() {
  if (m_eglDisplay != EGL_NO_DISPLAY && m_eglSurface != EGL_NO_SURFACE && m_eglContext != EGL_NO_CONTEXT) {
    eglMakeCurrent(m_eglDisplay, m_eglSurface, m_eglSurface, m_eglContext);
  }
}

void WallpaperRenderer::resize(std::uint32_t bufferWidth, std::uint32_t bufferHeight, std::uint32_t logicalWidth,
                               std::uint32_t logicalHeight) {
  if (bufferWidth == 0 || bufferHeight == 0) {
    return;
  }

  if (m_surface == nullptr || m_eglDisplay == EGL_NO_DISPLAY || m_eglContext == EGL_NO_CONTEXT) {
    throw std::runtime_error("wallpaper renderer is not bound");
  }

  if (m_window == nullptr) {
    m_window = wl_egl_window_create(m_surface, static_cast<int>(bufferWidth), static_cast<int>(bufferHeight));
    if (m_window == nullptr) {
      throw std::runtime_error("wl_egl_window_create failed");
    }

    m_eglSurface =
        eglCreateWindowSurface(m_eglDisplay, m_eglConfig, reinterpret_cast<EGLNativeWindowType>(m_window), nullptr);
    if (m_eglSurface == EGL_NO_SURFACE) {
      throw std::runtime_error("eglCreateWindowSurface failed");
    }
  } else {
    wl_egl_window_resize(m_window, static_cast<int>(bufferWidth), static_cast<int>(bufferHeight), 0, 0);
  }

  eglMakeCurrent(m_eglDisplay, m_eglSurface, m_eglSurface, m_eglContext);

  m_bufferWidth = bufferWidth;
  m_bufferHeight = bufferHeight;
  m_logicalWidth = logicalWidth;
  m_logicalHeight = logicalHeight;

  glViewport(0, 0, static_cast<GLsizei>(bufferWidth), static_cast<GLsizei>(bufferHeight));

  m_program.ensureInitialized();
}

void WallpaperRenderer::render() {
  if (m_eglSurface == EGL_NO_SURFACE || m_tex1 == 0) {
    return;
  }

  eglMakeCurrent(m_eglDisplay, m_eglSurface, m_eglSurface, m_eglContext);
  glViewport(0, 0, static_cast<GLsizei>(m_bufferWidth), static_cast<GLsizei>(m_bufferHeight));
  glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
  glClear(GL_COLOR_BUFFER_BIT);

  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

  auto sw = static_cast<float>(m_logicalWidth);
  auto sh = static_cast<float>(m_logicalHeight);

  // If no second texture, just draw the first using fade at progress 0
  GLuint tex2 = (m_tex2 != 0) ? m_tex2 : m_tex1;
  float progress = (m_tex2 != 0) ? m_progress : 0.0f;

  m_program.draw(m_transition, m_tex1, tex2, sw, sh, m_imgW1, m_imgH1, m_imgW2, m_imgH2, progress,
                 static_cast<float>(m_fillMode), m_params);

  eglSwapBuffers(m_eglDisplay, m_eglSurface);
}

void WallpaperRenderer::renderToFbo(GLuint targetFbo) {
  if (m_eglSurface == EGL_NO_SURFACE || m_tex1 == 0) {
    return;
  }

  eglMakeCurrent(m_eglDisplay, m_eglSurface, m_eglSurface, m_eglContext);
  glBindFramebuffer(GL_FRAMEBUFFER, targetFbo);
  glViewport(0, 0, static_cast<GLsizei>(m_bufferWidth), static_cast<GLsizei>(m_bufferHeight));
  glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
  glClear(GL_COLOR_BUFFER_BIT);

  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

  auto sw = static_cast<float>(m_logicalWidth);
  auto sh = static_cast<float>(m_logicalHeight);

  GLuint tex2 = (m_tex2 != 0) ? m_tex2 : m_tex1;
  float progress = (m_tex2 != 0) ? m_progress : 0.0f;

  m_program.draw(m_transition, m_tex1, tex2, sw, sh, m_imgW1, m_imgH1, m_imgW2, m_imgH2, progress,
                 static_cast<float>(m_fillMode), m_params);
  // No eglSwapBuffers — caller is responsible for presentation
}

void WallpaperRenderer::swapBuffers() { eglSwapBuffers(m_eglDisplay, m_eglSurface); }

void WallpaperRenderer::setTransitionState(GLuint tex1, GLuint tex2, float imgW1, float imgH1, float imgW2, float imgH2,
                                           float progress, WallpaperTransition transition, WallpaperFillMode fillMode,
                                           const TransitionParams& params) {
  m_tex1 = tex1;
  m_tex2 = tex2;
  m_imgW1 = imgW1;
  m_imgH1 = imgH1;
  m_imgW2 = imgW2;
  m_imgH2 = imgH2;
  m_progress = progress;
  m_transition = transition;
  m_fillMode = fillMode;
  m_params = params;
}

void WallpaperRenderer::cleanup() {
  m_program.destroy();

  if (m_eglDisplay != EGL_NO_DISPLAY) {
    eglMakeCurrent(m_eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (m_eglSurface != EGL_NO_SURFACE) {
      eglDestroySurface(m_eglDisplay, m_eglSurface);
    }
    if (m_eglContext != EGL_NO_CONTEXT) {
      eglDestroyContext(m_eglDisplay, m_eglContext);
    }
  }

  if (m_window != nullptr) {
    wl_egl_window_destroy(m_window);
  }
}
