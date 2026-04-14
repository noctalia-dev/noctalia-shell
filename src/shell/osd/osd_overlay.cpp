#include "core/ui_phase.h"
#include "shell/osd/osd_overlay.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/log.h"
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

constexpr float kCardWidth = Style::controlHeightLg * 7 + Style::spaceMd + Style::spaceSm;
constexpr float kCardHeight = Style::controlHeightLg + Style::spaceXs;
constexpr int kSurfaceWidth = static_cast<int>(kCardWidth + Style::spaceSm);
constexpr int kSurfaceHeight = static_cast<int>(kCardHeight + Style::spaceLg);
constexpr int kHideDelayMs = Style::animSlow * 3 + Style::animFast * 2;

constexpr float kCardOpacity = 0.98f;
constexpr float kGlyphSize = Style::fontSizeTitle + Style::borderWidth * 4;
constexpr float kValueFontSize = Style::fontSizeBody;

constexpr float kProgressHeight = Style::spaceXs + Style::borderWidth * 2;
constexpr float kCardPadding = Style::spaceMd;
constexpr float kInnerGap = Style::spaceSm + Style::spaceXs;
constexpr int kScreenMargin = static_cast<int>(Style::spaceLg);
constexpr int kBarGap = static_cast<int>(Style::spaceXs);

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
  if (!m_instances.empty() && position != m_lastPosition) {
    destroySurfaces();
  }

  if (!m_instances.empty() && m_instances.size() != m_wayland->outputs().size()) {
    destroySurfaces();
  }
  if (!m_instances.empty()) {
    return;
  }

  m_lastPosition = position;

  const auto surfaceWidth = static_cast<std::uint32_t>(kSurfaceWidth);
  const auto surfaceHeight = static_cast<std::uint32_t>(kSurfaceHeight);
  std::int32_t barHeight = Style::barHeightDefault;
  std::string barPosition = "top";
  if (m_config != nullptr && !m_config->config().bars.empty()) {
    barHeight = m_config->config().bars[0].height;
    barPosition = m_config->config().bars[0].position;
  }

  for (const auto& output : m_wayland->outputs()) {
    auto inst = std::make_unique<Instance>();
    inst->output = output.output;
    inst->scale = output.scale;

    std::uint32_t anchor = LayerShellAnchor::Top | LayerShellAnchor::Right;
    std::int32_t marginTop = kScreenMargin;
    std::int32_t marginRight = kScreenMargin;
    std::int32_t marginBottom = 0;
    std::int32_t marginLeft = 0;

    if (position == "top_left") {
      anchor = LayerShellAnchor::Top | LayerShellAnchor::Left;
      marginRight = 0;
      marginLeft = kScreenMargin;
    } else if (position == "top_center") {
      anchor = LayerShellAnchor::Top;
      marginRight = 0;
    } else if (position == "bottom_left") {
      anchor = LayerShellAnchor::Bottom | LayerShellAnchor::Left;
      marginTop = 0;
      marginRight = 0;
      marginBottom = kScreenMargin;
      marginLeft = kScreenMargin;
    } else if (position == "bottom_center") {
      anchor = LayerShellAnchor::Bottom;
      marginTop = 0;
      marginRight = 0;
      marginBottom = kScreenMargin;
    } else if (position == "bottom_right") {
      anchor = LayerShellAnchor::Bottom | LayerShellAnchor::Right;
      marginTop = 0;
      marginBottom = kScreenMargin;
    }

    if ((position == "top_left" || position == "top_center" || position == "top_right") && barPosition == "top") {
      marginTop += barHeight + kBarGap;
    }
    if ((position == "bottom_left" || position == "bottom_center" || position == "bottom_right") &&
        barPosition == "bottom") {
      marginBottom += barHeight + kBarGap;
    }

    auto surfaceConfig = LayerSurfaceConfig{
        .nameSpace = "noctalia-osd",
        .layer = LayerShellLayer::Overlay,
        .anchor = anchor,
        .width = surfaceWidth,
        .height = surfaceHeight,
        .exclusiveZone = -1,
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

  const bool needsSceneBuild =
      inst.sceneRoot == nullptr || static_cast<std::uint32_t>(std::round(inst.sceneRoot->width())) != width ||
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

  inst.sceneRoot = std::make_unique<Node>();
  inst.sceneRoot->setSize(w, h);
  inst.sceneRoot->setOpacity(0.0f);
  inst.surface->setSceneRoot(inst.sceneRoot.get());

  const float cardX = (w - kCardWidth) * 0.5f;
  const float cardY = (h - kCardHeight) * 0.5f;

  auto background = std::make_unique<Box>();
  background->setCardStyle();
  background->setFill(roleColor(ColorRole::Surface));
  background->setBorder(roleColor(ColorRole::Outline), Style::borderWidth);
  background->setRadius(kCardHeight * 0.5f);
  background->setSoftness(1.2f);
  background->setSize(kCardWidth, kCardHeight);
  background->setPosition(cardX, cardY);
  background->setZIndex(0);
  inst.background = background.get();
  inst.sceneRoot->addChild(std::move(background));

  auto card = std::make_unique<Node>();
  card->setSize(kCardWidth, kCardHeight);
  card->setPosition(cardX, cardY);
  card->setZIndex(1);
  inst.card = card.get();

  auto row = std::make_unique<Flex>();
  row->setDirection(FlexDirection::Horizontal);
  row->setAlign(FlexAlign::Center);
  row->setJustify(FlexJustify::Start);
  row->setGap(kInnerGap);
  row->setSize(kCardWidth - kCardPadding * 2.0f, kCardHeight);
  row->setZIndex(1);
  inst.row = row.get();

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyphSize(kGlyphSize);
  glyph->setColor(roleColor(ColorRole::Primary));
  inst.glyph = glyph.get();
  inst.glyph->setZIndex(1);
  inst.row->addChild(std::move(glyph));

  auto value = std::make_unique<Label>();
  value->setBold(true);
  value->setFontSize(kValueFontSize);
  value->setColor(roleColor(ColorRole::OnSurface));
  inst.value = value.get();
  inst.value->setZIndex(1);

  auto progress = std::make_unique<ProgressBar>();
  progress->setTrack(roleColor(ColorRole::Surface));
  progress->setFill(roleColor(ColorRole::Primary));
  progress->setFlexGrow(1.0f);
  progress->setSize(0.0f, kProgressHeight);
  progress->setRadius(kProgressHeight * 0.5);
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

  inst.glyph->setGlyph(m_content.icon);
  inst.value->setText(m_content.value);
  inst.progress->setRadius(kProgressHeight * 0.5f);
  inst.progress->setProgress(m_content.progress);
  inst.row->layout(*m_renderContext);
  inst.row->setPosition(kCardPadding, std::round((inst.card->height() - inst.row->height()) * 0.5f));
}

void OsdOverlay::animateInstance(Instance& inst) {
  if (inst.sceneRoot == nullptr) {
    return;
  }

  if (inst.hideAnimId != 0) {
    inst.animations.cancel(inst.hideAnimId);
    inst.hideAnimId = 0;
  }

  const float baseY = (inst.sceneRoot->height() - kCardHeight) * 0.5f;
  if (!inst.visible) {
    // During fast updates (e.g. slider drag), don't restart the show animation
    // every tick; keep the current show motion and only extend hide timing.
    if (inst.showAnimId == 0) {
      const float startOpacity = inst.sceneRoot->opacity();
      if (startOpacity == 0.0f) {
        inst.card->setPosition(inst.card->x(), baseY + 8.0f);
        if (inst.background != nullptr) {
          inst.background->setPosition(inst.background->x(), baseY + 8.0f);
        }
      }
      inst.showAnimId = inst.animations.animate(
          startOpacity, 1.0f, Style::animNormal, Easing::EaseOutCubic,
          [&inst, baseY](float v) {
            inst.sceneRoot->setOpacity(v);
            inst.card->setPosition(inst.card->x(), baseY + (1.0f - v) * 8.0f);
            if (inst.background != nullptr) {
              inst.background->setPosition(inst.background->x(), baseY + (1.0f - v) * 8.0f);
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
      [this, &inst, baseY]() {
        inst.hideAnimId = inst.animations.animate(
            1.0f, 0.0f, Style::animNormal, Easing::EaseInOutQuad,
            [&inst, baseY](float v) {
              inst.sceneRoot->setOpacity(v);
              inst.card->setPosition(inst.card->x(), baseY + (1.0f - v) * 6.0f);
              if (inst.background != nullptr) {
                inst.background->setPosition(inst.background->x(), baseY + (1.0f - v) * 6.0f);
              }
            },
            [this, &inst]() {
              inst.hideAnimId = 0;
              inst.visible = false;
              DeferredCall::callLater([this]() {
                const bool allHidden = std::all_of(m_instances.begin(), m_instances.end(),
                    [](const auto& i) { return !i->visible; });
                if (allHidden) {
                  destroySurfaces();
                }
              });
            });
      });
}
