#include "shell/osd/osd_overlay.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "core/ui_phase.h"
#include "render/render_context.h"
#include "render/scene/node.h"
#include "ui/controls/box.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <cmath>

namespace {

  constexpr Logger kLog("osd");

  constexpr int kHideDelayMs = Style::animSlow * 3 + Style::animFast * 2;

  [[nodiscard]] float osdUiScale(const ConfigService* config) {
    if (config == nullptr) {
      return 1.0f;
    }
    return std::max(0.1f, config->config().shell.uiScale);
  }

  // Base units at ui_scale=1; passive overlay (no hit targets), between bar and old OSD size.
  [[nodiscard]] float cardWidth(float s) {
    return (Style::controlHeight * 6 + Style::spaceMd + Style::spaceSm + Style::spaceXs) * s;
  }

  [[nodiscard]] float cardHeight(float s) { return (Style::controlHeight + Style::spaceSm) * s; }

  [[nodiscard]] std::uint32_t osdSurfaceWidth(float s) {
    const float w = cardWidth(s) + Style::spaceMd * s;
    return static_cast<std::uint32_t>(std::max(1, static_cast<int>(std::ceil(w))));
  }

  [[nodiscard]] std::uint32_t osdSurfaceHeight(float s) {
    const float h = cardHeight(s) + Style::spaceLg * s;
    return static_cast<std::uint32_t>(std::max(1, static_cast<int>(std::ceil(h))));
  }

  [[nodiscard]] float glyphSize(float s) { return (Style::fontSizeTitle + Style::borderWidth * 4) * s; }

  [[nodiscard]] float valueFontSize(float s) { return Style::fontSizeBody * s; }

  [[nodiscard]] float progressHeight(float s) { return (Style::spaceXs + Style::borderWidth * 2) * s; }

  [[nodiscard]] float cardPadding(float s) { return Style::spaceMd * s; }

  [[nodiscard]] float innerGap(float s) { return (Style::spaceSm + Style::spaceXs * 0.5f) * s; }

  [[nodiscard]] float slideOffset(float s) { return Style::spaceSm * s; }

  [[nodiscard]] int screenMargin(float s) { return static_cast<int>(std::lround(Style::spaceSm * s)); }

  bool isBottomPosition(const std::string& position) { return position.starts_with("bottom_"); }

  float cardBaseYForPosition(const std::string& position, float surfaceHeight, float cardH) {
    return isBottomPosition(position) ? std::max(0.0f, surfaceHeight - cardH) : 0.0f;
  }

  float cardSlideDirectionForPosition(const std::string& position) { return isBottomPosition(position) ? -1.0f : 1.0f; }

} // namespace

void OsdOverlay::initialize(WaylandConnection& wayland, ConfigService* config, RenderContext* renderContext) {
  m_wayland = &wayland;
  m_config = config;
  m_renderContext = renderContext;
}

void OsdOverlay::requestRedraw() {
  for (auto& inst : m_instances) {
    if (inst->surface != nullptr) {
      inst->surface->requestRedraw();
    }
  }
}

void OsdOverlay::requestLayout() {
  for (auto& inst : m_instances) {
    if (inst->surface != nullptr) {
      inst->surface->requestLayout();
    }
  }
}

void OsdOverlay::show(const OsdContent& content) {
  if (m_wayland == nullptr || m_renderContext == nullptr) {
    return;
  }

  m_content = content;
  ensureSurfaces();
  for (auto& inst : m_instances) {
    if (inst->surface == nullptr) {
      continue;
    }
    inst->showPending = true;
    inst->surface->requestUpdate();
  }
}

void OsdOverlay::ensureSurfaces() {
  if (m_wayland == nullptr || m_renderContext == nullptr) {
    return;
  }

  const std::string position =
      (m_config != nullptr && !m_config->config().osd.position.empty()) ? m_config->config().osd.position : "top_right";
  const float layoutScale = osdUiScale(m_config);

  if (!m_instances.empty() && position != m_lastPosition) {
    destroySurfaces();
  }

  if (!m_instances.empty() && std::abs(layoutScale - m_lastLayoutScale) > 1.0e-4f) {
    destroySurfaces();
  }

  if (!m_instances.empty() && m_instances.size() != m_wayland->outputs().size()) {
    destroySurfaces();
  }
  if (!m_instances.empty()) {
    return;
  }

  m_lastPosition = position;
  m_lastLayoutScale = layoutScale;

  const auto surfaceWidth = osdSurfaceWidth(layoutScale);
  const auto surfaceHeight = osdSurfaceHeight(layoutScale);
  const int margin = screenMargin(layoutScale);

  for (const auto& output : m_wayland->outputs()) {
    auto inst = std::make_unique<Instance>();
    inst->output = output.output;
    inst->scale = output.scale;
    inst->uiLayoutScale = layoutScale;

    std::uint32_t anchor = LayerShellAnchor::Top | LayerShellAnchor::Right;
    std::int32_t marginTop = margin;
    std::int32_t marginRight = margin;
    std::int32_t marginBottom = 0;
    std::int32_t marginLeft = 0;

    if (position == "top_left") {
      anchor = LayerShellAnchor::Top | LayerShellAnchor::Left;
      marginRight = 0;
      marginLeft = margin;
    } else if (position == "top_center") {
      anchor = LayerShellAnchor::Top;
      marginRight = 0;
    } else if (position == "bottom_left") {
      anchor = LayerShellAnchor::Bottom | LayerShellAnchor::Left;
      marginTop = 0;
      marginRight = 0;
      marginBottom = margin;
      marginLeft = margin;
    } else if (position == "bottom_center") {
      anchor = LayerShellAnchor::Bottom;
      marginTop = 0;
      marginRight = 0;
      marginBottom = margin;
    } else if (position == "bottom_right") {
      anchor = LayerShellAnchor::Bottom | LayerShellAnchor::Right;
      marginTop = 0;
      marginBottom = margin;
    }

    auto surfaceConfig = LayerSurfaceConfig{
        .nameSpace = "noctalia-osd",
        .layer = LayerShellLayer::Overlay,
        .anchor = anchor,
        .width = surfaceWidth,
        .height = surfaceHeight,
        .exclusiveZone = 0,
        .marginTop = marginTop,
        .marginRight = marginRight,
        .marginBottom = marginBottom,
        .marginLeft = marginLeft,
        .keyboard = LayerShellKeyboard::None,
        .defaultWidth = surfaceWidth,
        .defaultHeight = surfaceHeight,
    };

    inst->surface = std::make_unique<LayerSurface>(*m_wayland, std::move(surfaceConfig));
    auto* instPtr = inst.get();
    inst->surface->setConfigureCallback(
        [instPtr](std::uint32_t /*width*/, std::uint32_t /*height*/) { instPtr->surface->requestLayout(); });
    inst->surface->setPrepareFrameCallback(
        [this, instPtr](bool needsUpdate, bool needsLayout) { prepareFrame(*instPtr, needsUpdate, needsLayout); });
    inst->surface->setAnimationManager(&inst->animations);
    inst->surface->setRenderContext(m_renderContext);

    if (!inst->surface->initialize(output.output)) {
      kLog.warn("osd overlay: failed to initialize surface on {}", output.connectorName);
      continue;
    }

    inst->surface->setInputRegion({});
    inst->wlSurface = inst->surface->wlSurface();
    m_instances.push_back(std::move(inst));
  }
}

void OsdOverlay::destroySurfaces() {
  for (auto& inst : m_instances) {
    inst->animations.cancelAll();
  }
  m_instances.clear();
}

void OsdOverlay::prepareFrame(Instance& inst, bool needsUpdate, bool needsLayout) {
  if (m_renderContext == nullptr || inst.surface == nullptr) {
    return;
  }

  const auto width = inst.surface->width();
  const auto height = inst.surface->height();
  if (width == 0 || height == 0) {
    return;
  }

  m_renderContext->makeCurrent(inst.surface->renderTarget());

  const bool needsSceneBuild = inst.sceneRoot == nullptr ||
                               static_cast<std::uint32_t>(std::round(inst.sceneRoot->width())) != width ||
                               static_cast<std::uint32_t>(std::round(inst.sceneRoot->height())) != height;
  if (needsSceneBuild) {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    buildScene(inst, width, height);
  }

  if ((needsUpdate || needsLayout || needsSceneBuild) && inst.sceneRoot != nullptr) {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    updateInstanceContent(inst);
  }

  if (needsUpdate && inst.showPending) {
    animateInstance(inst);
    inst.showPending = false;
  }
}

void OsdOverlay::buildScene(Instance& inst, std::uint32_t width, std::uint32_t height) {
  uiAssertNotRendering("OsdOverlay::buildScene");
  if (m_renderContext == nullptr) {
    return;
  }

  const float w = static_cast<float>(width);
  const float h = static_cast<float>(height);
  const float s = inst.uiLayoutScale;
  const float cw = cardWidth(s);
  const float ch = cardHeight(s);
  const float pad = cardPadding(s);
  const float gap = innerGap(s);
  const float border = Style::borderWidth * s;

  inst.sceneRoot = std::make_unique<Node>();
  inst.sceneRoot->setSize(w, h);
  inst.sceneRoot->setOpacity(0.0f);
  inst.surface->setSceneRoot(inst.sceneRoot.get());

  const float cardX = (w - cw) * 0.5f;
  const float cardY = cardBaseYForPosition(m_lastPosition, h, ch);

  auto background = std::make_unique<Box>();
  background->setCardStyle();
  background->setFill(colorSpecFromRole(ColorRole::Surface));
  background->setBorder(colorSpecFromRole(ColorRole::Outline), border);
  background->setRadius(ch * 0.5f);
  background->setSize(cw, ch);
  background->setPosition(cardX, cardY);
  background->setZIndex(0);
  inst.background = background.get();
  inst.sceneRoot->addChild(std::move(background));

  auto card = std::make_unique<Node>();
  card->setSize(cw, ch);
  card->setPosition(cardX, cardY);
  card->setZIndex(1);
  inst.card = card.get();

  auto row = std::make_unique<Flex>();
  row->setDirection(FlexDirection::Horizontal);
  row->setAlign(FlexAlign::Center);
  row->setJustify(FlexJustify::Start);
  row->setGap(gap);
  row->setSize(cw - pad * 2.0f, ch);
  row->setZIndex(1);
  inst.row = row.get();

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyphSize(glyphSize(s));
  glyph->setColor(colorSpecFromRole(ColorRole::Primary));
  inst.glyph = glyph.get();
  inst.glyph->setZIndex(1);
  inst.row->addChild(std::move(glyph));

  auto value = std::make_unique<Label>();
  value->setBold(true);
  value->setFontSize(valueFontSize(s));
  value->setColor(colorSpecFromRole(ColorRole::OnSurface));
  value->setTextAlign(TextAlign::End);
  // Reserve enough width for "100%" so the progress bar doesn't shrink at max values.
  value->setText("100%");
  value->measure(*m_renderContext);
  inst.progressValueMinWidth = value->width();
  value->setMinWidth(inst.progressValueMinWidth);
  value->setZIndex(1);
  inst.value = value.get();

  const float ph = progressHeight(s);
  auto progress = std::make_unique<ProgressBar>();
  progress->setTrack(colorSpecFromRole(ColorRole::SurfaceVariant));
  progress->setFill(colorSpecFromRole(ColorRole::Primary));
  progress->setFlexGrow(1.0f);
  progress->setSize(0.0f, ph);
  progress->setRadius(ph * 0.5f);
  inst.progress = progress.get();
  inst.progress->setZIndex(1);
  inst.row->addChild(std::move(progress));
  inst.row->addChild(std::move(value));
  inst.card->addChild(std::move(row));

  inst.sceneRoot->addChild(std::move(card));
}

void OsdOverlay::updateInstanceContent(Instance& inst) {
  if (m_renderContext == nullptr || inst.card == nullptr || inst.row == nullptr || inst.glyph == nullptr ||
      inst.value == nullptr || inst.progress == nullptr) {
    return;
  }

  const float s = inst.uiLayoutScale;

  inst.glyph->setGlyph(m_content.icon);
  inst.progress->setVisible(m_content.showProgress);
  inst.row->setJustify(m_content.showProgress ? FlexJustify::Start : FlexJustify::Center);
  inst.value->setTextAlign(m_content.showProgress ? TextAlign::End : TextAlign::Center);
  inst.value->setMinWidth(m_content.showProgress ? inst.progressValueMinWidth : 0.0f);
  inst.value->setText(m_content.value);
  inst.progress->setRadius(progressHeight(s) * 0.5f);
  inst.progress->setProgress(m_content.progress);
  inst.row->layout(*m_renderContext);
  inst.row->setPosition(cardPadding(s), std::round((inst.card->height() - inst.row->height()) * 0.5f));
}

void OsdOverlay::animateInstance(Instance& inst) {
  if (inst.sceneRoot == nullptr) {
    return;
  }

  if (inst.hideAnimId != 0) {
    inst.animations.cancel(inst.hideAnimId);
    inst.hideAnimId = 0;
  }

  const float s = inst.uiLayoutScale;
  const float ch = cardHeight(s);
  const float baseY = cardBaseYForPosition(m_lastPosition, inst.sceneRoot->height(), ch);
  const float slideDirection = cardSlideDirectionForPosition(m_lastPosition);
  const float slidePx = slideOffset(s);
  if (!inst.visible) {
    // During fast updates (e.g. slider drag), don't restart the show animation
    // every tick; keep the current show motion and only extend hide timing.
    if (inst.showAnimId == 0) {
      const float startOpacity = inst.sceneRoot->opacity();
      if (startOpacity == 0.0f) {
        inst.card->setPosition(inst.card->x(), baseY + slideDirection * slidePx);
        if (inst.background != nullptr) {
          inst.background->setPosition(inst.background->x(), baseY + slideDirection * slidePx);
        }
      }
      inst.showAnimId = inst.animations.animate(
          startOpacity, 1.0f, Style::animNormal, Easing::EaseOutCubic,
          [&inst, baseY, slideDirection, slidePx](float v) {
            inst.sceneRoot->setOpacity(v);
            inst.card->setPosition(inst.card->x(), baseY + slideDirection * (1.0f - v) * slidePx);
            if (inst.background != nullptr) {
              inst.background->setPosition(inst.background->x(), baseY + slideDirection * (1.0f - v) * slidePx);
            }
          },
          [&inst]() {
            inst.showAnimId = 0;
            inst.visible = true;
          });
    }
  } else {
    inst.sceneRoot->setOpacity(1.0f);
    inst.card->setPosition(inst.card->x(), baseY);
    if (inst.background != nullptr) {
      inst.background->setPosition(inst.background->x(), baseY);
    }
  }

  inst.hideAnimId = inst.animations.animate(
      1.0f, 0.0f, kHideDelayMs, Easing::Linear, [](float /*v*/) {},
      [this, &inst, baseY, slideDirection, slidePx]() {
        inst.hideAnimId = inst.animations.animate(
            1.0f, 0.0f, Style::animNormal, Easing::EaseInOutQuad,
            [&inst, baseY, slideDirection, slidePx](float v) {
              inst.sceneRoot->setOpacity(v);
              inst.card->setPosition(inst.card->x(), baseY + slideDirection * (1.0f - v) * slidePx);
              if (inst.background != nullptr) {
                inst.background->setPosition(inst.background->x(), baseY + slideDirection * (1.0f - v) * slidePx);
              }
            },
            [this, &inst]() {
              inst.hideAnimId = 0;
              inst.visible = false;
              DeferredCall::callLater([this]() {
                const bool allIdle = std::all_of(m_instances.begin(), m_instances.end(), [](const auto& i) {
                  return !i->visible && !i->showPending && i->showAnimId == 0 && i->hideAnimId == 0;
                });
                if (allIdle) {
                  destroySurfaces();
                }
              });
            });
      });
}
