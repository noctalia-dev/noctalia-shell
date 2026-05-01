#include "render/backend/gles_render_backend.h"

#include "core/log.h"
#include "render/gl_shared_context.h"
#include "render/render_target.h"

#include <GLES2/gl2.h>
#include <chrono>
#include <format>
#include <stdexcept>
#include <utility>

namespace {

  constexpr Logger kLog("render");
  constexpr float kSlowRenderOperationDebugMs = 50.0f;
  constexpr float kSlowRenderOperationWarnMs = 1000.0f;

  constexpr EGLint kContextAttributes[] = {
      EGL_CONTEXT_CLIENT_VERSION,
      2,
      EGL_NONE,
  };

  const char* safeCString(const char* value) { return value != nullptr ? value : "unknown"; }

  float elapsedSince(std::chrono::steady_clock::time_point start) {
    return std::chrono::duration<float, std::milli>(std::chrono::steady_clock::now() - start).count();
  }

  template <typename... Args> void logSlowRenderOperation(float ms, std::format_string<Args...> fmt, Args&&... args) {
    if (ms >= kSlowRenderOperationWarnMs) {
      kLog.warn(fmt, std::forward<Args>(args)...);
    } else if (ms >= kSlowRenderOperationDebugMs) {
      kLog.debug(fmt, std::forward<Args>(args)...);
    }
  }

} // namespace

GlesRenderBackend::~GlesRenderBackend() { cleanup(); }

void GlesRenderBackend::initialize(GlSharedContext& shared) {
  m_native.display = shared.display();
  m_native.config = shared.config();

  m_native.context = eglCreateContext(m_native.display, m_native.config, shared.rootContext(), kContextAttributes);
  if (m_native.context == EGL_NO_CONTEXT) {
    throw std::runtime_error("eglCreateContext failed");
  }

  // Make context current (surfaceless) so GL resources can be created eagerly.
  makeCurrentNoSurface();

  kLog.info("EGL vendor=\"{}\" version=\"{}\" APIs=\"{}\"", safeCString(eglQueryString(m_native.display, EGL_VENDOR)),
            safeCString(eglQueryString(m_native.display, EGL_VERSION)),
            safeCString(eglQueryString(m_native.display, EGL_CLIENT_APIS)));
  kLog.info("OpenGL ES vendor=\"{}\" renderer=\"{}\" version=\"{}\"",
            safeCString(reinterpret_cast<const char*>(glGetString(GL_VENDOR))),
            safeCString(reinterpret_cast<const char*>(glGetString(GL_RENDERER))),
            safeCString(reinterpret_cast<const char*>(glGetString(GL_VERSION))));
}

void GlesRenderBackend::makeCurrentNoSurface() {
  if (m_native.display == EGL_NO_DISPLAY || m_native.context == EGL_NO_CONTEXT) {
    return;
  }

  if (eglMakeCurrent(m_native.display, EGL_NO_SURFACE, EGL_NO_SURFACE, m_native.context) != EGL_TRUE) {
    throw std::runtime_error("eglMakeCurrent(EGL_NO_SURFACE) failed");
  }
}

void GlesRenderBackend::makeCurrent(RenderTarget& target) {
  const auto start = std::chrono::steady_clock::now();
  if (eglMakeCurrent(m_native.display, target.eglSurface(), target.eglSurface(), m_native.context) != EGL_TRUE) {
    throw std::runtime_error("eglMakeCurrent failed");
  }
  float ms = elapsedSince(start);
  logSlowRenderOperation(ms, "eglMakeCurrent took {:.1f}ms", ms);

  // Non-blocking swap: pacing is driven by wl_surface.frame callbacks, not by
  // eglSwapBuffers. Default interval=1 can block indefinitely when the
  // compositor holds our buffer.
  const auto intervalStart = std::chrono::steady_clock::now();
  eglSwapInterval(m_native.display, 0);
  ms = elapsedSince(intervalStart);
  logSlowRenderOperation(ms, "eglSwapInterval(0) took {:.1f}ms", ms);
}

void GlesRenderBackend::beginFrame(RenderTarget& target) {
  makeCurrent(target);

  glViewport(0, 0, static_cast<GLint>(target.bufferWidth()), static_cast<GLint>(target.bufferHeight()));
  glEnable(GL_BLEND);
  glBlendFuncSeparate(GL_ONE, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

  glDisable(GL_SCISSOR_TEST);
  glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
  glClear(GL_COLOR_BUFFER_BIT);
}

void GlesRenderBackend::endFrame(RenderTarget& target) {
  const auto swapStart = std::chrono::steady_clock::now();
  if (eglSwapBuffers(m_native.display, target.eglSurface()) != EGL_TRUE) {
    throw std::runtime_error("eglSwapBuffers failed");
  }
  const float ms = elapsedSince(swapStart);
  logSlowRenderOperation(ms, "eglSwapBuffers took {:.1f}ms ({}x{} logical, {}x{} buffer)", ms, target.logicalWidth(),
                         target.logicalHeight(), target.bufferWidth(), target.bufferHeight());
}

void GlesRenderBackend::cleanup() {
  if (m_native.display != EGL_NO_DISPLAY && m_native.context != EGL_NO_CONTEXT) {
    eglMakeCurrent(m_native.display, EGL_NO_SURFACE, EGL_NO_SURFACE, m_native.context);
  }

  m_textureManager.cleanup();

  if (m_native.display != EGL_NO_DISPLAY) {
    eglMakeCurrent(m_native.display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  }

  if (m_native.context != EGL_NO_CONTEXT && m_native.display != EGL_NO_DISPLAY) {
    eglDestroyContext(m_native.display, m_native.context);
  }

  m_native = {};
}
