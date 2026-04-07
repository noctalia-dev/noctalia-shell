#include "render/render_context.h"
#include "render/render_target.h"
#include "render/scene/glyph_node.h"
#include "render/scene/image_node.h"
#include "render/scene/node.h"
#include "render/scene/rect_node.h"
#include "render/scene/spinner_node.h"
#include "render/scene/text_node.h"

#include "ui/style.h"

#include <algorithm>
#include <cmath>
#include <stdexcept>
#include <vector>

#include <GLES2/gl2.h>

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

namespace {

void applyScissor(float sw, float sh, float bw, float bh, float left, float top, float right, float bottom) {
  const float scaleX = sw > 0.0f ? bw / sw : 1.0f;
  const float scaleY = sh > 0.0f ? bh / sh : 1.0f;

  const GLint scissorX = static_cast<GLint>(std::floor(left * scaleX));
  const GLint scissorY = static_cast<GLint>(std::floor((sh - bottom) * scaleY));
  const GLsizei scissorW = static_cast<GLsizei>(std::ceil(std::max(0.0f, right - left) * scaleX));
  const GLsizei scissorH = static_cast<GLsizei>(std::ceil(std::max(0.0f, bottom - top) * scaleY));
  glScissor(scissorX, scissorY, scissorW, scissorH);
}

} // namespace

RenderContext::RenderContext() = default;

RenderContext::~RenderContext() { cleanup(); }

void RenderContext::initialize(wl_display* display) {
  if (display == nullptr) {
    throw std::runtime_error("RenderContext requires a valid Wayland display");
  }

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

  // Make context current (surfaceless) so we can create GL resources eagerly.
  // This allows measureText/measureGlyph to work before any surface exists.
  eglMakeCurrent(m_eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, m_eglContext);

  const auto fonts = m_fontService.resolveFallbackChain("sans-serif");
  m_textRenderer.initialize(fonts);
  const auto boldFonts = m_fontService.resolveFallbackChain("sans-serif", 8, FC_WEIGHT_BOLD);
  m_boldTextRenderer.initialize(boldFonts);
  m_iconTextRenderer.initialize({{NOCTALIA_ASSETS_DIR "/fonts/tabler-icons.ttf", 0}});
  ensureGlPrograms();

  // Pre-warm the glyph atlas so first use doesn't stall.
  // Printable ASCII covers most UI text; common icons cover bar/panel widgets.
  (void)m_textRenderer.measure(
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 !@#$%^&*()-_=+[]{}|;:',.<>?/\"",
      Style::fontSizeBody);
}

void RenderContext::ensureGlPrograms() {
  if (m_glReady) {
    return;
  }
  m_imageProgram.ensureInitialized();
  m_linearGradientProgram.ensureInitialized();
  m_roundedRectProgram.ensureInitialized();
  m_spinnerProgram.ensureInitialized();
  m_glReady = true;
}

void RenderContext::makeCurrent(RenderTarget& target) {
  if (eglMakeCurrent(m_eglDisplay, target.eglSurface(), target.eglSurface(), m_eglContext) != EGL_TRUE) {
    throw std::runtime_error("eglMakeCurrent failed");
  }
}

void RenderContext::renderScene(RenderTarget& target, Node* sceneRoot) {
  makeCurrent(target);
  ensureGlPrograms();

  glViewport(0, 0, static_cast<GLint>(target.bufferWidth()), static_cast<GLint>(target.bufferHeight()));
  glEnable(GL_BLEND);
  glBlendFuncSeparate(GL_ONE, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

  glDisable(GL_SCISSOR_TEST);
  glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
  glClear(GL_COLOR_BUFFER_BIT);

  if (sceneRoot != nullptr) {
    const auto sw = static_cast<float>(target.logicalWidth());
    const auto sh = static_cast<float>(target.logicalHeight());
    const auto bw = static_cast<float>(target.bufferWidth());
    const auto bh = static_cast<float>(target.bufferHeight());
    renderNode(sceneRoot, 0.0f, 0.0f, 1.0f, sw, sh, bw, bh, 0.0f, 0.0f, sw, sh, false);
  }

  if (eglSwapBuffers(m_eglDisplay, target.eglSurface()) != EGL_TRUE) {
    throw std::runtime_error("eglSwapBuffers failed");
  }
}

TextMetrics RenderContext::measureText(std::string_view text, float fontSize, bool bold) {
  auto m = bold ? m_boldTextRenderer.measure(text, fontSize) : m_textRenderer.measure(text, fontSize);
  return TextMetrics{.width = m.width, .top = m.top, .bottom = m.bottom};
}

TextMetrics RenderContext::measureGlyph(char32_t codepoint, float fontSize) {
  auto m = m_iconTextRenderer.measureGlyph(codepoint, fontSize);
  return TextMetrics{.width = m.width, .top = m.top, .bottom = m.bottom};
}

TextureManager& RenderContext::textureManager() { return m_textureManager; }

void RenderContext::renderNode(const Node* node, float parentX, float parentY, float parentOpacity, float sw, float sh,
                               float bw, float bh, float clipLeft, float clipTop, float clipRight, float clipBottom,
                               bool hasClip) {
  if (!node->visible()) {
    return;
  }

  const float absX = parentX + node->x();
  const float absY = parentY + node->y();
  const float absRight = absX + node->width();
  const float absBottom = absY + node->height();
  const float effectiveOpacity = parentOpacity * node->opacity();
  const float rot = node->rotation();
  const float scl = node->scale();

  if (hasClip) {
    glEnable(GL_SCISSOR_TEST);
    applyScissor(sw, sh, bw, bh, clipLeft, clipTop, clipRight, clipBottom);
  } else {
    glDisable(GL_SCISSOR_TEST);
  }

  switch (node->type()) {
  case NodeType::Rect: {
    const auto* rect = static_cast<const RectNode*>(node);
    auto style = rect->style();
    style.fill.a *= effectiveOpacity;
    style.fillEnd.a *= effectiveOpacity;
    style.border.a *= effectiveOpacity;
    m_roundedRectProgram.draw(sw, sh, absX, absY, node->width(), node->height(), style, rot, scl);
    break;
  }
  case NodeType::Text: {
    const auto* text = static_cast<const TextNode*>(node);
    if (!text->text().empty()) {
      auto color = text->color();
      color.a *= effectiveOpacity;
      auto& renderer = text->bold() ? m_boldTextRenderer : m_textRenderer;
      if (text->maxWidth() > 0.0f) {
        auto truncated = renderer.truncate(text->text(), text->fontSize(), text->maxWidth());
        renderer.draw(sw, sh, absX, absY, truncated.text, text->fontSize(), color, rot, scl);
      } else {
        renderer.draw(sw, sh, absX, absY, text->text(), text->fontSize(), color, rot, scl);
      }
    }
    break;
  }
  case NodeType::Image: {
    const auto* img = static_cast<const ImageNode*>(node);
    if (img->textureId() != 0) {
      auto tint = img->tint();
      tint.a *= effectiveOpacity;
      m_imageProgram.draw(img->textureId(), sw, sh, absX, absY, node->width(), node->height(), tint, effectiveOpacity,
                          rot, scl);
    }
    break;
  }
  case NodeType::Glyph: {
    const auto* icon = static_cast<const GlyphNode*>(node);
    if (icon->codepoint() != 0) {
      auto color = icon->color();
      color.a *= effectiveOpacity;
      m_iconTextRenderer.drawGlyph(sw, sh, absX, absY, icon->codepoint(), icon->fontSize(), color, rot, scl);
    }
    break;
  }
  case NodeType::Spinner: {
    const auto* spinner = static_cast<const SpinnerNode*>(node);
    auto style = spinner->style();
    style.color.a *= effectiveOpacity;
    m_spinnerProgram.draw(sw, sh, absX, absY, node->width(), node->height(), style, rot, scl);
    break;
  }
  case NodeType::Base:
    break;
  }

  std::vector<const Node*> orderedChildren;
  orderedChildren.reserve(node->children().size());
  for (const auto& child : node->children()) {
    orderedChildren.push_back(child.get());
  }
  std::stable_sort(orderedChildren.begin(), orderedChildren.end(),
                   [](const Node* a, const Node* b) { return a->zIndex() < b->zIndex(); });

  float childClipLeft = clipLeft;
  float childClipTop = clipTop;
  float childClipRight = clipRight;
  float childClipBottom = clipBottom;
  bool childHasClip = hasClip;

  if (node->clipChildren()) {
    childClipLeft = hasClip ? std::max(childClipLeft, absX) : absX;
    childClipTop = hasClip ? std::max(childClipTop, absY) : absY;
    childClipRight = hasClip ? std::min(childClipRight, absRight) : absRight;
    childClipBottom = hasClip ? std::min(childClipBottom, absBottom) : absBottom;
    childHasClip = true;
  }

  if (childHasClip && (childClipRight <= childClipLeft || childClipBottom <= childClipTop)) {
    return;
  }

  for (const auto* child : orderedChildren) {
    renderNode(child, absX, absY, effectiveOpacity, sw, sh, bw, bh, childClipLeft, childClipTop, childClipRight,
               childClipBottom, childHasClip);
  }
}

void RenderContext::cleanup() {
  if (m_eglDisplay != EGL_NO_DISPLAY && m_eglContext != EGL_NO_CONTEXT) {
    // Need a current context to destroy GL resources, but we may not have a surface.
    // Use EGL_NO_SURFACE — this is valid for destroying resources when no surface exists.
    eglMakeCurrent(m_eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, m_eglContext);
  }

  m_textureManager.cleanup();
  m_imageProgram.destroy();
  m_linearGradientProgram.destroy();
  m_roundedRectProgram.destroy();
  m_spinnerProgram.destroy();
  m_textRenderer.cleanup();
  m_boldTextRenderer.cleanup();
  m_iconTextRenderer.cleanup();
  m_glReady = false;

  eglMakeCurrent(m_eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);

  if (m_eglContext != EGL_NO_CONTEXT) {
    eglDestroyContext(m_eglDisplay, m_eglContext);
    m_eglContext = EGL_NO_CONTEXT;
  }

  if (m_eglDisplay != EGL_NO_DISPLAY) {
    eglTerminate(m_eglDisplay);
    m_eglDisplay = EGL_NO_DISPLAY;
  }

  m_eglConfig = nullptr;
}
