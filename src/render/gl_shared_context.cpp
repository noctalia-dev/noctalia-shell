#include "render/gl_shared_context.h"

#include "core/log.h"

#include <stdexcept>

namespace {

  constexpr Logger kLog("gl");

  constexpr EGLint kConfigAttributes[] = {
      EGL_SURFACE_TYPE,
      EGL_WINDOW_BIT,
      EGL_RENDERABLE_TYPE,
      EGL_OPENGL_ES2_BIT,
      EGL_RED_SIZE,
      8,
      EGL_GREEN_SIZE,
      8,
      EGL_BLUE_SIZE,
      8,
      EGL_ALPHA_SIZE,
      8,
      EGL_NONE,
  };

  // GLES 3, not 2. libprojectM 4.x renders through Vertex Array Objects,
  // which are not core in GLES2 — under an ES2 context its VAO/element-buffer
  // binding silently no-ops, Mesa then treats libprojectM's VBO index offset
  // as a client-side pointer and memcpys from a garbage address, crashing
  // deterministically inside FinalComposite::Draw on the first frame. GLES3 is
  // a strict superset of GLES2, so every other (ES2-targeted) renderer in the
  // share group keeps working unchanged. The driver advertises ES 3.2.
  constexpr EGLint kContextAttributes[] = {
      EGL_CONTEXT_CLIENT_VERSION,
      3,
      EGL_NONE,
  };

} // namespace

GlSharedContext::~GlSharedContext() { cleanup(); }

void GlSharedContext::initialize(wl_display* display) {
  if (display == nullptr) {
    throw std::runtime_error("GlSharedContext requires a valid Wayland display");
  }

  m_display = eglGetDisplay(reinterpret_cast<EGLNativeDisplayType>(display));
  if (m_display == EGL_NO_DISPLAY) {
    throw std::runtime_error("eglGetDisplay failed");
  }

  EGLint major = 0;
  EGLint minor = 0;
  if (eglInitialize(m_display, &major, &minor) != EGL_TRUE) {
    throw std::runtime_error("eglInitialize failed");
  }

  if (eglBindAPI(EGL_OPENGL_ES_API) != EGL_TRUE) {
    throw std::runtime_error("eglBindAPI failed");
  }

  EGLint configCount = 0;
  if (eglChooseConfig(m_display, kConfigAttributes, &m_config, 1, &configCount) != EGL_TRUE || configCount != 1) {
    throw std::runtime_error("eglChooseConfig failed");
  }

  m_rootContext = eglCreateContext(m_display, m_config, EGL_NO_CONTEXT, kContextAttributes);
  if (m_rootContext == EGL_NO_CONTEXT) {
    throw std::runtime_error("eglCreateContext (root) failed");
  }

  kLog.info("initialized EGL {}.{} with shared root context", major, minor);
}

void GlSharedContext::makeCurrentSurfaceless() const {
  if (m_display == EGL_NO_DISPLAY || m_rootContext == EGL_NO_CONTEXT) {
    return;
  }
  if (eglMakeCurrent(m_display, EGL_NO_SURFACE, EGL_NO_SURFACE, m_rootContext) != EGL_TRUE) {
    throw std::runtime_error("eglMakeCurrent (root, surfaceless) failed");
  }
}

void GlSharedContext::cleanup() {
  if (m_display == EGL_NO_DISPLAY) {
    return;
  }

  eglMakeCurrent(m_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);

  if (m_rootContext != EGL_NO_CONTEXT) {
    eglDestroyContext(m_display, m_rootContext);
    m_rootContext = EGL_NO_CONTEXT;
  }

  eglTerminate(m_display);
  m_display = EGL_NO_DISPLAY;
  m_config = nullptr;
}
