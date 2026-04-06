#include "shell/osd/osd_overlay.h"

#include "config/config_service.h"
#include "core/log.h"
#include "render/render_context.h"
#include "render/scene/node.h"
#include "ui/controls/box.h"
#include "ui/controls/icon.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <cmath>

namespace {

constexpr int kSurfaceWidth = 360;
constexpr int kSurfaceHeight = 76;
constexpr int kCardWidth = 348;
constexpr int kCardHeight = 52;
constexpr int kHideDelayMs = 1400;

constexpr float kCardOpacity = 0.98f;
constexpr float kIconSize = 20.0f;
constexpr float kValueFontSize = static_cast<float>(Style::fontSizeTitle);

constexpr float kProgressHeight = 8.0f;
constexpr float kCardPadding = static_cast<float>(Style::spaceMd);
constexpr float kInnerGap = static_cast<float>(Style::spaceMd);
constexpr int kScreenMargin = Style::spaceLg;
constexpr int kBarGap = 4;

} // namespace

void OsdOverlay::initialize(WaylandConnection& wayland, ConfigService* config, RenderContext* renderContext) {
  m_wayland = &wayland;
  m_config = config;
  m_renderContext = renderContext;
}

void OsdOverlay::show(const OsdContent& content) {
  if (m_wayland == nullptr || m_renderContext == nullptr) {
    return;
  }

  m_content = content;
  ensureSurfaces();
  for (auto& inst : m_instances) {
    if (inst->sceneRoot == nullptr) {
      continue;
    }
    updateInstanceContent(*inst);
    animateInstance(*inst);
    inst->surface->requestRedraw();
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
    inst->surface->setConfigureCallback([this, instPtr](std::uint32_t width, std::uint32_t height) {
      buildScene(*instPtr, width, height);
    });
    inst->surface->setAnimationManager(&inst->animations);
    inst->surface->setRenderContext(m_renderContext);

    if (!inst->surface->initialize(output.output, output.scale)) {
      logWarn("osd overlay: failed to initialize surface on {}", output.connectorName);
      continue;
    }

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

void OsdOverlay::buildScene(Instance& inst, std::uint32_t width, std::uint32_t height) {
  if (m_renderContext == nullptr) {
    return;
  }

  const float w = static_cast<float>(width);
  const float h = static_cast<float>(height);

  inst.sceneRoot = std::make_unique<Node>();
  inst.sceneRoot->setSize(w, h);
  inst.sceneRoot->setOpacity(0.0f);
  inst.surface->setSceneRoot(inst.sceneRoot.get());

  const float cardX = (w - static_cast<float>(kCardWidth)) * 0.5f;
  const float cardY = (h - static_cast<float>(kCardHeight)) * 0.5f;

  auto background = std::make_unique<Box>();
  background->setCardStyle();
  background->setFill(palette.surface);
  background->setBorder(palette.outline, static_cast<float>(Style::borderWidth));
  background->setRadius(static_cast<float>(kCardHeight) * 0.5f);
  background->setSoftness(1.2f);
  background->setSize(static_cast<float>(kCardWidth), static_cast<float>(kCardHeight));
  background->setPosition(cardX, cardY);
  background->setZIndex(0);
  inst.background = background.get();
  inst.sceneRoot->addChild(std::move(background));

  auto card = std::make_unique<Node>();
  card->setSize(static_cast<float>(kCardWidth), static_cast<float>(kCardHeight));
  card->setPosition(cardX, cardY);
  card->setZIndex(1);
  inst.card = card.get();

  auto icon = std::make_unique<Icon>();
  icon->setIconSize(kIconSize);
  icon->setColor(palette.primary);
  inst.icon = icon.get();
  inst.icon->setZIndex(1);
  inst.card->addChild(std::move(icon));

  auto value = std::make_unique<Label>();
  value->setBold(true);
  value->setFontSize(kValueFontSize);
  value->setColor(palette.onSurface);
  inst.value = value.get();
  inst.value->setZIndex(1);
  inst.card->addChild(std::move(value));

  auto progress = std::make_unique<ProgressBar>();
  progress->setRadius(static_cast<float>(Style::radiusFull));
  progress->setTrackColor(palette.surface);
  progress->setFillColor(palette.primary);
  inst.progress = progress.get();
  inst.progress->setZIndex(1);
  inst.card->addChild(std::move(progress));

  inst.sceneRoot->addChild(std::move(card));
  updateInstanceContent(inst);
}

void OsdOverlay::updateInstanceContent(Instance& inst) {
  if (m_renderContext == nullptr || inst.card == nullptr || inst.icon == nullptr || inst.value == nullptr ||
      inst.progress == nullptr) {
    return;
  }

  const float cardWidth = inst.card->width();
  inst.icon->setIcon(m_content.icon);
  inst.icon->measure(*m_renderContext);
  inst.icon->setPosition(kCardPadding,
                         std::round((inst.card->height() - inst.icon->height()) * 0.5f) - 1.0f);

  inst.value->setText(m_content.value);
  inst.value->setMaxWidth(cardWidth);
  inst.value->measure(*m_renderContext);
  inst.value->setPosition(cardWidth - kCardPadding - inst.value->width(),
                          std::round((inst.card->height() - inst.value->height()) * 0.5f));

  const float progressX = inst.icon->x() + inst.icon->width() + kInnerGap;
  const float progressWidth = std::max(0.0f, inst.value->x() - progressX - kInnerGap);
  inst.progress->setSize(progressWidth, kProgressHeight);
  inst.progress->setRadius(kProgressHeight * 0.5f);
  inst.progress->setPosition(progressX, std::round((inst.card->height() - kProgressHeight) * 0.5f));
  inst.progress->setProgress(m_content.progress);
}

void OsdOverlay::animateInstance(Instance& inst) {
  if (inst.sceneRoot == nullptr) {
    return;
  }

  if (inst.showAnimId != 0) {
    inst.animations.cancel(inst.showAnimId);
    inst.showAnimId = 0;
  }
  if (inst.hideAnimId != 0) {
    inst.animations.cancel(inst.hideAnimId);
    inst.hideAnimId = 0;
  }

  const float baseY = (inst.sceneRoot->height() - static_cast<float>(kCardHeight)) * 0.5f;
  if (!inst.visible) {
    inst.sceneRoot->setOpacity(0.0f);
    inst.card->setPosition(inst.card->x(), baseY + 8.0f);
    if (inst.background != nullptr) {
      inst.background->setPosition(inst.background->x(), baseY + 8.0f);
    }
    inst.showAnimId = inst.animations.animate(
        0.0f, 1.0f, Style::animNormal, Easing::EaseOutCubic,
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
  } else {
    inst.sceneRoot->setOpacity(1.0f);
    inst.card->setPosition(inst.card->x(), baseY);
    if (inst.background != nullptr) {
      inst.background->setPosition(inst.background->x(), baseY);
    }
  }

  inst.hideAnimId = inst.animations.animate(
      1.0f, 0.0f, kHideDelayMs, Easing::Linear, [](float /*v*/) {},
      [&inst, baseY]() {
        inst.hideAnimId = inst.animations.animate(
            1.0f, 0.0f, Style::animNormal, Easing::EaseInOutQuad,
            [&inst, baseY](float v) {
              inst.sceneRoot->setOpacity(v);
              inst.card->setPosition(inst.card->x(), baseY + (1.0f - v) * 6.0f);
              if (inst.background != nullptr) {
                inst.background->setPosition(inst.background->x(), baseY + (1.0f - v) * 6.0f);
              }
            },
            [&inst]() {
              inst.hideAnimId = 0;
              inst.visible = false;
            });
      });
}
