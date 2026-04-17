#include "render/render_context.h"
#include "core/log.h"
#include "core/ui_phase.h"
#include "render/gl_shared_context.h"
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
#include <optional>
#include <stdexcept>
#include <vector>

#include <GLES2/gl2.h>

namespace {

  constexpr Logger kLog("render");

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

  Mat3 nodeLocalTransform(const Node* node) {
    const float cx = node->width() * 0.5f;
    const float cy = node->height() * 0.5f;
    return Mat3::translation(node->x(), node->y()) * Mat3::translation(cx, cy) * Mat3::rotation(node->rotation()) *
           Mat3::scale(node->scale(), node->scale()) * Mat3::translation(-cx, -cy);
  }

} // namespace

RenderContext::RenderContext() = default;

RenderContext::~RenderContext() { cleanup(); }

void RenderContext::initialize(GlSharedContext& shared) {
  m_eglDisplay = shared.display();
  m_eglConfig = shared.config();

  m_eglContext = eglCreateContext(m_eglDisplay, m_eglConfig, shared.rootContext(), kContextAttributes);
  if (m_eglContext == EGL_NO_CONTEXT) {
    throw std::runtime_error("eglCreateContext failed");
  }

  // Make context current (surfaceless) so we can create GL resources eagerly.
  // This allows measureText/measureGlyph to work before any surface exists.
  eglMakeCurrent(m_eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, m_eglContext);

  // Pango handles font fallback via Fontconfig automatically — no explicit chain.
  ensureGlPrograms();
  m_textRenderer.initialize(&m_glyphProgram);
  m_glyphRenderer.initialize(NOCTALIA_ASSETS_DIR "/fonts/tabler.ttf", &m_glyphProgram);
}

void RenderContext::ensureGlPrograms() {
  if (m_glReady) {
    return;
  }
  m_imageProgram.ensureInitialized();
  m_linearGradientProgram.ensureInitialized();
  m_rectProgram.ensureInitialized();
  m_spinnerProgram.ensureInitialized();
  m_glyphProgram.ensureInitialized();
  m_glReady = true;
}

void RenderContext::makeCurrentNoSurface() {
  if (m_eglDisplay == EGL_NO_DISPLAY || m_eglContext == EGL_NO_CONTEXT) {
    return;
  }

  if (eglMakeCurrent(m_eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, m_eglContext) != EGL_TRUE) {
    throw std::runtime_error("eglMakeCurrent(EGL_NO_SURFACE) failed");
  }
}

void RenderContext::makeCurrent(RenderTarget& target) {
  if (eglMakeCurrent(m_eglDisplay, target.eglSurface(), target.eglSurface(), m_eglContext) != EGL_TRUE) {
    throw std::runtime_error("eglMakeCurrent failed");
  }
  // Non-blocking swap: pacing is driven by wl_surface.frame callbacks, not by
  // eglSwapBuffers. Default interval=1 blocks indefinitely in Mesa when the
  // compositor holds our buffer (e.g. niri direct-scanout of a fullscreen
  // client occludes our overlay layer), which would freeze the whole main loop.
  eglSwapInterval(m_eglDisplay, 0);
}

void RenderContext::syncContentScale(RenderTarget& target) {
  const auto sw = static_cast<float>(target.logicalWidth());
  const auto bw = static_cast<float>(target.bufferWidth());
  const float contentScale = sw > 0.0f ? bw / sw : 1.0f;
  m_textRenderer.setContentScale(contentScale);
  m_glyphRenderer.setContentScale(contentScale);
}

void RenderContext::setTextFontFamily(std::string family) {
  makeCurrentNoSurface();
  m_textRenderer.setFontFamily(std::move(family));
}

void RenderContext::renderScene(RenderTarget& target, Node* sceneRoot) {
  UiPhaseScope renderPhase(UiPhase::Render);
  makeCurrent(target);
  ensureGlPrograms();
  syncContentScale(target);

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
    renderNode(sceneRoot, Mat3::identity(), 1.0f, sw, sh, bw, bh, 0.0f, 0.0f, sw, sh, false);
  }

  if (eglSwapBuffers(m_eglDisplay, target.eglSurface()) != EGL_TRUE) {
    throw std::runtime_error("eglSwapBuffers failed");
  }
}

TextMetrics RenderContext::measureText(std::string_view text, float fontSize, bool bold, float maxWidth, int maxLines,
                                       TextAlign align) {
  auto m = m_textRenderer.measure(text, fontSize, bold, maxWidth, maxLines, align);
  return TextMetrics{.width = m.width, .left = m.left, .right = m.right, .top = m.top, .bottom = m.bottom};
}

TextMetrics RenderContext::measureGlyph(char32_t codepoint, float fontSize) {
  auto m = m_glyphRenderer.measureGlyph(codepoint, fontSize);
  return TextMetrics{.width = m.width, .left = m.left, .right = m.right, .top = m.top, .bottom = m.bottom};
}

TextureManager& RenderContext::textureManager() {
  makeCurrentNoSurface();
  return m_textureManager;
}

void RenderContext::renderNode(const Node* node, const Mat3& parentTransform, float parentOpacity, float sw, float sh,
                               float bw, float bh, float clipLeft, float clipTop, float clipRight, float clipBottom,
                               bool hasClip) {
  if (!node->visible()) {
    return;
  }

  const Mat3 worldTransform = parentTransform * nodeLocalTransform(node);
  const float effectiveOpacity = parentOpacity * node->opacity();
  float boundsLeft = 0.0f;
  float boundsTop = 0.0f;
  float boundsRight = 0.0f;
  float boundsBottom = 0.0f;
  Node::transformedBounds(node, worldTransform, boundsLeft, boundsTop, boundsRight, boundsBottom);

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
    m_rectProgram.draw(sw, sh, node->width(), node->height(), style, worldTransform);
    break;
  }
  case NodeType::Text: {
    const auto* text = static_cast<const TextNode*>(node);
    if (!text->text().empty()) {
      auto color = text->color();
      color.a *= effectiveOpacity;
      m_textRenderer.draw(sw, sh, 0.0f, 0.0f, text->text(), text->fontSize(), color, worldTransform, text->bold(),
                          text->maxWidth(), text->maxLines(), text->textAlign());
    }
    break;
  }
  case NodeType::Image: {
    const auto* img = static_cast<const ImageNode*>(node);
    if (img->textureId() != 0) {
      auto tint = img->tint();
      tint.a *= effectiveOpacity;
      m_imageProgram.draw(img->textureId(), sw, sh, node->width(), node->height(), tint, effectiveOpacity,
                          img->cornerRadius(), img->borderColor(), img->borderWidth(), static_cast<int>(img->fitMode()),
                          static_cast<float>(img->textureWidth()), static_cast<float>(img->textureHeight()),
                          worldTransform);
    }
    break;
  }
  case NodeType::Glyph: {
    const auto* icon = static_cast<const GlyphNode*>(node);
    if (icon->codepoint() != 0) {
      auto color = icon->color();
      color.a *= effectiveOpacity;
      m_glyphRenderer.drawGlyph(sw, sh, 0.0f, 0.0f, icon->codepoint(), icon->fontSize(), color, worldTransform);
    }
    break;
  }
  case NodeType::Spinner: {
    const auto* spinner = static_cast<const SpinnerNode*>(node);
    auto style = spinner->style();
    style.color.a *= effectiveOpacity;
    m_spinnerProgram.draw(sw, sh, node->width(), node->height(), style, worldTransform);
    break;
  }
  case NodeType::Base:
    break;
  }

  // Fast path: children are already in zIndex order (the common case — most
  // callers never touch zIndex, or set it identically across siblings). Skip
  // allocating/sorting a side vector and iterate the child list directly.
  // Only fall back to the sorted copy when there's an actual out-of-order
  // pair, which removes a per-node heap allocation from every rendered frame.
  const auto& children = node->children();
  bool childrenSorted = true;
  for (std::size_t i = 1; i < children.size(); ++i) {
    if (children[i]->zIndex() < children[i - 1]->zIndex()) {
      childrenSorted = false;
      break;
    }
  }

  std::vector<const Node*> orderedChildren;
  if (!childrenSorted) {
    orderedChildren.reserve(children.size());
    for (const auto& child : children) {
      orderedChildren.push_back(child.get());
    }
    std::stable_sort(orderedChildren.begin(), orderedChildren.end(),
                     [](const Node* a, const Node* b) { return a->zIndex() < b->zIndex(); });
  }

  float childClipLeft = clipLeft;
  float childClipTop = clipTop;
  float childClipRight = clipRight;
  float childClipBottom = clipBottom;
  bool childHasClip = hasClip;

  if (node->clipChildren()) {
    childClipLeft = hasClip ? std::max(childClipLeft, boundsLeft) : boundsLeft;
    childClipTop = hasClip ? std::max(childClipTop, boundsTop) : boundsTop;
    childClipRight = hasClip ? std::min(childClipRight, boundsRight) : boundsRight;
    childClipBottom = hasClip ? std::min(childClipBottom, boundsBottom) : boundsBottom;
    childHasClip = true;
  }

  if (childHasClip && (childClipRight <= childClipLeft || childClipBottom <= childClipTop)) {
    return;
  }

  if (childrenSorted) {
    for (const auto& child : children) {
      renderNode(child.get(), worldTransform, effectiveOpacity, sw, sh, bw, bh, childClipLeft, childClipTop,
                 childClipRight, childClipBottom, childHasClip);
    }
  } else {
    for (const auto* child : orderedChildren) {
      renderNode(child, worldTransform, effectiveOpacity, sw, sh, bw, bh, childClipLeft, childClipTop, childClipRight,
                 childClipBottom, childHasClip);
    }
  }
}

void RenderContext::cleanup() {
  if (m_eglDisplay != EGL_NO_DISPLAY && m_eglContext != EGL_NO_CONTEXT) {
    // Need a current context to destroy GL resources, but we may not have a surface.
    // Use EGL_NO_SURFACE — this is valid for destroying resources when no surface exists.
    eglMakeCurrent(m_eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, m_eglContext);
  }

  // Text renderers first — they destroy GL textures and need a current context.
  m_textRenderer.cleanup();
  m_glyphRenderer.cleanup();
  m_textureManager.cleanup();
  m_imageProgram.destroy();
  m_linearGradientProgram.destroy();
  m_rectProgram.destroy();
  m_spinnerProgram.destroy();
  m_glyphProgram.destroy();
  m_glReady = false;

  if (m_eglDisplay != EGL_NO_DISPLAY) {
    eglMakeCurrent(m_eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  }

  if (m_eglContext != EGL_NO_CONTEXT && m_eglDisplay != EGL_NO_DISPLAY) {
    eglDestroyContext(m_eglDisplay, m_eglContext);
  }
  m_eglContext = EGL_NO_CONTEXT;

  // The EGLDisplay and EGLConfig belong to GlSharedContext — do not terminate
  // or forget them. Just clear our references.
  m_eglDisplay = EGL_NO_DISPLAY;
  m_eglConfig = nullptr;
}
