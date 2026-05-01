#include "render/render_context.h"

#include "core/log.h"
#include "core/resource_paths.h"
#include "core/ui_phase.h"
#include "render/backend/gles_render_backend.h"
#include "render/gl_shared_context.h"
#include "render/render_target.h"
#include "render/scene/effect_node.h"
#include "render/scene/glyph_node.h"
#include "render/scene/graph_node.h"
#include "render/scene/image_node.h"
#include "render/scene/node.h"
#include "render/scene/rect_node.h"
#include "render/scene/spinner_node.h"
#include "render/scene/text_node.h"
#include "render/scene/wallpaper_node.h"
#include "ui/style.h"

#include <GLES2/gl2.h>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <format>
#include <optional>
#include <stdexcept>
#include <utility>
#include <vector>

namespace {

  constexpr Logger kLog("render");
  constexpr float kSlowRenderOperationDebugMs = 50.0f;
  constexpr float kSlowRenderOperationWarnMs = 1000.0f;

} // namespace

namespace {

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
  cleanup();
  m_backend = std::make_unique<GlesRenderBackend>();
  m_backend->initialize(shared);

  // Pango handles font fallback via Fontconfig automatically — no explicit chain.
  ensureGlPrograms();
  m_backend->textureManager().probeExtensions();
  m_textRenderer.initialize(&m_glyphProgram);
  m_glyphRenderer.initialize(paths::assetPath("fonts/tabler.ttf").string(), &m_glyphProgram);
}

void RenderContext::ensureGlPrograms() {
  if (m_glReady) {
    return;
  }
  m_effectProgram.ensureInitialized();
  m_graphProgram.ensureInitialized();
  m_imageProgram.ensureInitialized();
  m_linearGradientProgram.ensureInitialized();
  m_rectProgram.ensureInitialized();
  m_spinnerProgram.ensureInitialized();
  m_wallpaperProgram.ensureInitialized();
  m_glyphProgram.ensureInitialized();
  m_glReady = true;
}

void RenderContext::makeCurrentNoSurface() {
  if (m_backend == nullptr) {
    return;
  }
  m_backend->makeCurrentNoSurface();
}

void RenderContext::makeCurrent(RenderTarget& target) {
  if (m_backend == nullptr) {
    throw std::runtime_error("RenderContext has no initialized backend");
  }
  m_backend->makeCurrent(target);
}

void RenderContext::syncContentScale(RenderTarget& target) {
  const auto sw = static_cast<float>(target.logicalWidth());
  const auto bw = static_cast<float>(target.bufferWidth());
  m_renderScale = sw > 0.0f ? std::max(1.0f, bw / sw) : 1.0f;
  m_textRenderer.setContentScale(m_renderScale);
  m_glyphRenderer.setContentScale(m_renderScale);
}

void RenderContext::setTextFontFamily(std::string family) {
  makeCurrentNoSurface();
  m_textRenderer.setFontFamily(std::move(family));
}

void RenderContext::renderScene(RenderTarget& target, Node* sceneRoot) {
  UiPhaseScope renderPhase(UiPhase::Render);
  if (m_backend == nullptr) {
    return;
  }
  const auto totalStart = std::chrono::steady_clock::now();
  m_backend->beginFrame(target);
  ensureGlPrograms();
  syncContentScale(target);

  const auto drawStart = std::chrono::steady_clock::now();
  if (sceneRoot != nullptr) {
    const auto sw = static_cast<float>(target.logicalWidth());
    const auto sh = static_cast<float>(target.logicalHeight());
    const auto bw = static_cast<float>(target.bufferWidth());
    const auto bh = static_cast<float>(target.bufferHeight());
    renderNode(sceneRoot, Mat3::identity(), 1.0f, sw, sh, bw, bh, 0.0f, 0.0f, sw, sh, false);
  }
  float ms = elapsedSince(drawStart);
  logSlowRenderOperation(ms, "scene draw took {:.1f}ms ({}x{} logical, {}x{} buffer)", ms, target.logicalWidth(),
                         target.logicalHeight(), target.bufferWidth(), target.bufferHeight());

  m_backend->endFrame(target);
  ms = elapsedSince(totalStart);
  logSlowRenderOperation(ms, "renderScene took {:.1f}ms total", ms);
}

TextMetrics RenderContext::measureText(std::string_view text, float fontSize, bool bold, float maxWidth, int maxLines,
                                       TextAlign align) {
  auto m = m_textRenderer.measure(text, fontSize, bold, maxWidth, maxLines, align);
  return TextMetrics{.width = m.width,
                     .left = m.left,
                     .right = m.right,
                     .top = m.top,
                     .bottom = m.bottom,
                     .inkTop = m.inkTop,
                     .inkBottom = m.inkBottom,
                     .inkLeft = m.inkLeft,
                     .inkRight = m.inkRight};
}

TextMetrics RenderContext::measureGlyph(char32_t codepoint, float fontSize) {
  auto m = m_glyphRenderer.measureGlyph(codepoint, fontSize);
  return TextMetrics{.width = m.width,
                     .left = m.left,
                     .right = m.right,
                     .top = m.top,
                     .bottom = m.bottom,
                     .inkTop = m.top,
                     .inkBottom = m.bottom,
                     .inkLeft = m.left,
                     .inkRight = m.right};
}

TextureManager& RenderContext::textureManager() {
  makeCurrentNoSurface();
  return m_backend->textureManager();
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
      if (text->hasShadow()) {
        auto shadowColor = text->shadowColor();
        shadowColor.a *= effectiveOpacity;
        const Mat3 shadowTransform = worldTransform * Mat3::translation(text->shadowOffsetX(), text->shadowOffsetY());
        m_textRenderer.draw(sw, sh, 0.0f, 0.0f, text->text(), text->fontSize(), shadowColor, shadowTransform,
                            text->bold(), text->maxWidth(), text->maxLines(), text->textAlign());
      }
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
                          img->radius(), img->borderColor(), img->borderWidth(), static_cast<int>(img->fitMode()),
                          static_cast<float>(img->textureWidth()), static_cast<float>(img->textureHeight()),
                          worldTransform);
    }
    break;
  }
  case NodeType::Glyph: {
    const auto* icon = static_cast<const GlyphNode*>(node);
    if (icon->codepoint() != 0) {
      if (icon->hasShadow()) {
        auto shadowColor = icon->shadowColor();
        shadowColor.a *= effectiveOpacity;
        const Mat3 shadowTransform = worldTransform * Mat3::translation(icon->shadowOffsetX(), icon->shadowOffsetY());
        m_glyphRenderer.drawGlyph(sw, sh, 0.0f, 0.0f, icon->codepoint(), icon->fontSize(), shadowColor,
                                  shadowTransform);
      }
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
  case NodeType::Effect: {
    const auto* effect = static_cast<const EffectNode*>(node);
    auto style = effect->style();
    style.bgColor.a *= effectiveOpacity;
    m_effectProgram.draw(sw, sh, node->width(), node->height(), style, worldTransform);
    break;
  }
  case NodeType::Graph: {
    const auto* graph = static_cast<const GraphNode*>(node);
    if (graph->textureId() != 0) {
      auto style = graph->style();
      style.lineColor1.a *= effectiveOpacity;
      style.lineColor2.a *= effectiveOpacity;
      style.graphFillOpacity *= effectiveOpacity;
      m_graphProgram.draw(graph->textureId(), graph->textureWidth(), sw, sh, node->width(), node->height(), style,
                          worldTransform);
    }
    break;
  }
  case NodeType::Wallpaper: {
    const auto* wallpaper = static_cast<const WallpaperNode*>(node);
    const bool hasSource1 = wallpaper->sourceKind1() == WallpaperSourceKind::Color || wallpaper->texture1() != 0;
    if (hasSource1) {
      const bool hasSource2 = wallpaper->sourceKind2() == WallpaperSourceKind::Color || wallpaper->texture2() != 0;
      const WallpaperSourceKind sourceKind2 = hasSource2 ? wallpaper->sourceKind2() : wallpaper->sourceKind1();
      const std::uint32_t texture2 = hasSource2 ? wallpaper->texture2() : wallpaper->texture1();
      const Color& sourceColor2 = hasSource2 ? wallpaper->sourceColor2() : wallpaper->sourceColor1();
      const float imageWidth2 = hasSource2 ? wallpaper->imageWidth2() : wallpaper->imageWidth1();
      const float imageHeight2 = hasSource2 ? wallpaper->imageHeight2() : wallpaper->imageHeight1();
      const float progress = hasSource2 ? wallpaper->progress() : 0.0f;
      m_wallpaperProgram.draw(wallpaper->transition(), wallpaper->sourceKind1(), wallpaper->texture1(),
                              wallpaper->sourceColor1(), sourceKind2, texture2, sourceColor2, sw, sh, node->width(),
                              node->height(), wallpaper->imageWidth1(), wallpaper->imageHeight1(), imageWidth2,
                              imageHeight2, progress, static_cast<float>(wallpaper->fillMode()),
                              wallpaper->transitionParams(), wallpaper->fillColor(), worldTransform);
    }
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
  if (m_backend != nullptr) {
    // Need a current context to destroy GL resources, but we may not have a surface.
    m_backend->makeCurrentNoSurface();
  }

  // Text renderers first — they destroy GL textures and need a current context.
  m_textRenderer.cleanup();
  m_glyphRenderer.cleanup();
  if (m_backend != nullptr) {
    m_backend->textureManager().cleanup();
  }
  m_effectProgram.destroy();
  m_graphProgram.destroy();
  m_imageProgram.destroy();
  m_linearGradientProgram.destroy();
  m_rectProgram.destroy();
  m_spinnerProgram.destroy();
  m_wallpaperProgram.destroy();
  m_glyphProgram.destroy();
  m_glReady = false;

  if (m_backend != nullptr) {
    m_backend->cleanup();
    m_backend.reset();
  }
}

EGLDisplay RenderContext::eglDisplay() const noexcept {
  const auto* native = m_backend != nullptr ? m_backend->glesNative() : nullptr;
  return native != nullptr ? native->display : EGL_NO_DISPLAY;
}

EGLConfig RenderContext::eglConfig() const noexcept {
  const auto* native = m_backend != nullptr ? m_backend->glesNative() : nullptr;
  return native != nullptr ? native->config : nullptr;
}

EGLContext RenderContext::eglContext() const noexcept {
  const auto* native = m_backend != nullptr ? m_backend->glesNative() : nullptr;
  return native != nullptr ? native->context : EGL_NO_CONTEXT;
}
