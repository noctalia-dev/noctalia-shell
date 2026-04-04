#include "render/GlRenderer.h"
#include "render/scene/IconNode.h"
#include "render/scene/ImageNode.h"
#include "render/scene/Node.h"
#include "render/scene/RectNode.h"
#include "render/scene/TextNode.h"

#include <cstdint>
#include <stdexcept>

#include <GLES2/gl2.h>
#include <wayland-egl.h>

namespace {

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

constexpr EGLint kContextAttributes[] = {
    EGL_CONTEXT_CLIENT_VERSION,
    2,
    EGL_NONE,
};

} // namespace

GlRenderer::GlRenderer() = default;

GlRenderer::~GlRenderer() { cleanup(); }

const char* GlRenderer::name() const noexcept { return "gl"; }

void GlRenderer::bind(wl_display* display, wl_surface* surface) {
  if (display == nullptr || surface == nullptr) {
    throw std::runtime_error("OpenGL renderer requires a valid Wayland display and surface");
  }

  m_display = display;
  m_surface = surface;

  m_eglDisplay = eglGetDisplay(reinterpret_cast<EGLNativeDisplayType>(display));
  if (m_eglDisplay == EGL_NO_DISPLAY) {
    throw std::runtime_error("eglGetDisplay failed");
  }

  EGLint major = 0;
  EGLint minor = 0;
  if (eglInitialize(m_eglDisplay, &major, &minor) != EGL_TRUE) {
    throw std::runtime_error("eglInitialize failed");
  }

  if (eglBindAPI(EGL_OPENGL_ES_API) != EGL_TRUE) {
    throw std::runtime_error("eglBindAPI failed");
  }

  EGLint configCount = 0;
  if (eglChooseConfig(m_eglDisplay, kConfigAttributes, &m_eglConfig, 1, &configCount) != EGL_TRUE || configCount != 1) {
    throw std::runtime_error("eglChooseConfig failed");
  }

  m_eglContext = eglCreateContext(m_eglDisplay, m_eglConfig, EGL_NO_CONTEXT, kContextAttributes);
  if (m_eglContext == EGL_NO_CONTEXT) {
    throw std::runtime_error("eglCreateContext failed");
  }
}

void GlRenderer::makeCurrent() {
  if (m_eglDisplay != EGL_NO_DISPLAY && m_eglSurface != EGL_NO_SURFACE && m_eglContext != EGL_NO_CONTEXT) {
    eglMakeCurrent(m_eglDisplay, m_eglSurface, m_eglSurface, m_eglContext);
  }
}

void GlRenderer::resize(std::uint32_t bufferWidth, std::uint32_t bufferHeight, std::uint32_t logicalWidth,
                        std::uint32_t logicalHeight) {
  if (bufferWidth == 0 || bufferHeight == 0) {
    return;
  }

  if (m_surface == nullptr || m_eglDisplay == EGL_NO_DISPLAY || m_eglContext == EGL_NO_CONTEXT) {
    throw std::runtime_error("OpenGL renderer is not bound");
  }

  if (m_window == nullptr) {
    m_window = wl_egl_window_create(m_surface, static_cast<int>(bufferWidth), static_cast<int>(bufferHeight));
    if (m_window == nullptr) {
      throw std::runtime_error("wl_egl_window_create failed");
    }
  } else {
    wl_egl_window_resize(m_window, static_cast<int>(bufferWidth), static_cast<int>(bufferHeight), 0, 0);
  }

  if (m_eglSurface == EGL_NO_SURFACE) {
    m_eglSurface =
        eglCreateWindowSurface(m_eglDisplay, m_eglConfig, reinterpret_cast<EGLNativeWindowType>(m_window), nullptr);
    if (m_eglSurface == EGL_NO_SURFACE) {
      throw std::runtime_error("eglCreateWindowSurface failed");
    }
  }

  if (eglMakeCurrent(m_eglDisplay, m_eglSurface, m_eglSurface, m_eglContext) != EGL_TRUE) {
    throw std::runtime_error("eglMakeCurrent failed during resize");
  }

  m_bufferWidth = bufferWidth;
  m_bufferHeight = bufferHeight;
  m_logicalWidth = logicalWidth;
  m_logicalHeight = logicalHeight;
  m_imageProgram.ensureInitialized();
  m_linearGradientProgram.ensureInitialized();
  m_roundedRectProgram.ensureInitialized();
  const auto fonts = m_fontService.resolveFallbackChain("sans-serif");
  m_textRenderer.initialize(fonts);
  m_iconTextRenderer.initialize({{NOCTALIA_ASSETS_DIR "/fonts/tabler-icons.ttf", 0}});
}

void GlRenderer::render() {
  if (m_eglDisplay == EGL_NO_DISPLAY || m_eglSurface == EGL_NO_SURFACE || m_eglContext == EGL_NO_CONTEXT) {
    throw std::runtime_error("OpenGL renderer is not ready");
  }

  if (eglMakeCurrent(m_eglDisplay, m_eglSurface, m_eglSurface, m_eglContext) != EGL_TRUE) {
    throw std::runtime_error("eglMakeCurrent failed");
  }

  glViewport(0, 0, static_cast<GLint>(m_bufferWidth), static_cast<GLint>(m_bufferHeight));
  glEnable(GL_BLEND);
  glBlendFuncSeparate(GL_ONE, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

  glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
  glClear(GL_COLOR_BUFFER_BIT);

  if (m_sceneRoot != nullptr) {
    renderNode(m_sceneRoot, 0.0f, 0.0f, 1.0f);
  }

  if (eglSwapBuffers(m_eglDisplay, m_eglSurface) != EGL_TRUE) {
    throw std::runtime_error("eglSwapBuffers failed");
  }
}

void GlRenderer::setScene(Node* root) { m_sceneRoot = root; }

TextureManager& GlRenderer::textureManager() { return m_textureManager; }

TextMetrics GlRenderer::measureText(std::string_view text, float fontSize) {
  auto m = m_textRenderer.measure(text, fontSize);
  return TextMetrics{.width = m.width, .top = m.top, .bottom = m.bottom};
}

TextMetrics GlRenderer::measureGlyph(char32_t codepoint, float fontSize) {
  auto m = m_iconTextRenderer.measureGlyph(codepoint, fontSize);
  return TextMetrics{.width = m.width, .top = m.top, .bottom = m.bottom};
}

void GlRenderer::renderNode(const Node* node, float parentX, float parentY, float parentOpacity) {
  if (!node->visible()) {
    return;
  }

  const float absX = parentX + node->x();
  const float absY = parentY + node->y();
  const float effectiveOpacity = parentOpacity * node->opacity();

  const auto sw = static_cast<float>(m_logicalWidth);
  const auto sh = static_cast<float>(m_logicalHeight);

  switch (node->type()) {
  case NodeType::Rect: {
    const auto* rect = static_cast<const RectNode*>(node);
    auto style = rect->style();
    style.fill.a *= effectiveOpacity;
    style.fillEnd.a *= effectiveOpacity;
    style.border.a *= effectiveOpacity;
    m_roundedRectProgram.draw(sw, sh, absX, absY, node->width(), node->height(), style);
    break;
  }
  case NodeType::Text: {
    const auto* text = static_cast<const TextNode*>(node);
    if (!text->text().empty()) {
      auto color = text->color();
      color.a *= effectiveOpacity;
      if (text->maxWidth() > 0.0f) {
        auto truncated = m_textRenderer.truncate(text->text(), text->fontSize(), text->maxWidth());
        m_textRenderer.draw(sw, sh, absX, absY, truncated.text, text->fontSize(), color);
      } else {
        m_textRenderer.draw(sw, sh, absX, absY, text->text(), text->fontSize(), color);
      }
    }
    break;
  }
  case NodeType::Image: {
    const auto* img = static_cast<const ImageNode*>(node);
    if (img->textureId() != 0) {
      auto tint = img->tint();
      tint.a *= effectiveOpacity;
      m_imageProgram.draw(img->textureId(), sw, sh, absX, absY, node->width(), node->height(), tint, effectiveOpacity);
    }
    break;
  }
  case NodeType::Icon: {
    const auto* icon = static_cast<const IconNode*>(node);
    if (icon->codepoint() != 0) {
      auto color = icon->color();
      color.a *= effectiveOpacity;
      m_iconTextRenderer.drawGlyph(sw, sh, absX, absY, icon->codepoint(), icon->fontSize(), color);
    }
    break;
  }
  case NodeType::Base:
    break;
  }

  for (const auto& child : node->children()) {
    renderNode(child.get(), absX, absY, effectiveOpacity);
  }
}

void GlRenderer::cleanup() {
  m_textureManager.cleanup();
  m_imageProgram.destroy();
  m_linearGradientProgram.destroy();
  m_roundedRectProgram.destroy();
  m_textRenderer.cleanup();
  m_iconTextRenderer.cleanup();
  m_bufferWidth = 0;
  m_bufferHeight = 0;
  m_logicalWidth = 0;
  m_logicalHeight = 0;

  if (m_eglDisplay != EGL_NO_DISPLAY) {
    eglMakeCurrent(m_eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  }

  if (m_eglSurface != EGL_NO_SURFACE) {
    eglDestroySurface(m_eglDisplay, m_eglSurface);
    m_eglSurface = EGL_NO_SURFACE;
  }

  if (m_window != nullptr) {
    wl_egl_window_destroy(m_window);
    m_window = nullptr;
  }

  if (m_eglContext != EGL_NO_CONTEXT) {
    eglDestroyContext(m_eglDisplay, m_eglContext);
    m_eglContext = EGL_NO_CONTEXT;
  }

  if (m_eglDisplay != EGL_NO_DISPLAY) {
    eglTerminate(m_eglDisplay);
    m_eglDisplay = EGL_NO_DISPLAY;
  }

  m_eglConfig = nullptr;
  m_display = nullptr;
  m_surface = nullptr;
}
