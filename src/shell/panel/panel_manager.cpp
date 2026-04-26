#include "shell/panel/panel_manager.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "core/ui_phase.h"
#include "ipc/ipc_service.h"
#include "render/core/renderer.h"
#include "render/render_context.h"
#include "render/scene/rect_node.h"
#include "shell/surface_shadow.h"
#include "ui/controls/box.h"
#include "ui/controls/select.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/subsurface.h"
#include "wayland/wayland_connection.h"
#include "wayland/wayland_seat.h"

#include <algorithm>
#include <cmath>
#include <string>

PanelManager* PanelManager::s_instance = nullptr;

namespace {

  constexpr Logger kLog("panel");
  constexpr std::int32_t kAttachedPanelBarOverlap = 1;

  BarConfig resolvePanelBarConfig(ConfigService* configService, WaylandConnection* wayland, wl_output* output) {
    BarConfig barConfig;
    if (configService == nullptr || configService->config().bars.empty()) {
      return barConfig;
    }

    barConfig = configService->config().bars.front();
    if (wayland == nullptr || output == nullptr) {
      return barConfig;
    }

    if (const auto* wlOutput = wayland->findOutputByWl(output); wlOutput != nullptr) {
      return ConfigService::resolveForOutput(barConfig, *wlOutput);
    }

    return barConfig;
  }

  float resolvePanelContentScale(ConfigService* configService) {
    if (configService == nullptr) {
      return 1.0f;
    }
    return std::max(0.1f, configService->config().shell.uiScale);
  }

} // namespace

PanelManager::PanelManager() { s_instance = this; }

PanelManager::~PanelManager() {
  if (s_instance == this) {
    s_instance = nullptr;
  }
}

PanelManager& PanelManager::instance() { return *s_instance; }

void PanelManager::initialize(WaylandConnection& wayland, ConfigService* config, RenderContext* renderContext) {
  m_wayland = &wayland;
  m_config = config;
  m_renderContext = renderContext;
}

void PanelManager::setOpenSettingsWindowCallback(std::function<void()> callback) {
  m_openSettingsWindow = std::move(callback);
}

void PanelManager::openSettingsWindow() {
  if (m_openSettingsWindow) {
    m_openSettingsWindow();
  }
}

void PanelManager::setAttachedPanelParentResolver(
    std::function<std::optional<AttachedPanelParentContext>(wl_output*, std::string_view)> resolver) {
  m_attachedPanelParentResolver = std::move(resolver);
}

void PanelManager::setAttachedPanelGeometryCallback(
    std::function<void(wl_output*, std::optional<AttachedPanelGeometry>)> callback) {
  m_attachedPanelGeometryCallback = std::move(callback);
}

void PanelManager::setAttachedKeyboardCallbacks(std::function<void(wl_output*)> begin,
                                                std::function<void(wl_output*)> end) {
  m_beginAttachedKeyboard = std::move(begin);
  m_endAttachedKeyboard = std::move(end);
}

void PanelManager::registerPanel(const std::string& id, std::unique_ptr<Panel> content) {
  m_panels[id] = std::move(content);
}

void PanelManager::openPanel(const std::string& panelId, wl_output* output, float anchorX, float anchorY,
                             std::string_view context) {
  if (m_inTransition) {
    return;
  }

  // If a panel is open (or closing), destroy it immediately — no close animation when switching.
  // Bump the generation first so any in-flight deferred destroyPanel is a no-op.
  if (isOpen() || m_closing) {
    ++m_destroyGeneration;
    m_closing = false;
    destroyPanel();
  }

  auto it = m_panels.find(panelId);
  if (it == m_panels.end()) {
    kLog.warn("panel manager: unknown panel \"{}\"", panelId);
    return;
  }

  m_activePanel = it->second.get();
  m_activePanelId = panelId;
  m_activePanel->setContentScale(resolvePanelContentScale(m_config));
  m_pendingOpenContext = std::string(context);

  const auto panelWidth = static_cast<std::uint32_t>(m_activePanel->preferredWidth());
  const auto panelHeight = static_cast<std::uint32_t>(m_activePanel->preferredHeight());
  const auto barConfig = resolvePanelBarConfig(m_config, m_wayland, output);
  const bool isBottom = barConfig.position == "bottom";
  const bool isLeft = barConfig.position == "left";
  const bool isRight = barConfig.position == "right";
  const bool isVertical = isLeft || isRight;
  const std::int32_t panelGap = static_cast<std::int32_t>(Style::spaceXs);
  const std::int32_t screenPadding = static_cast<std::int32_t>(Style::spaceSm);

  std::int32_t outputWidth = static_cast<std::int32_t>(panelWidth);
  std::int32_t outputHeight = static_cast<std::int32_t>(panelHeight);
  if (m_wayland != nullptr) {
    const auto* wlOutput = m_wayland->findOutputByWl(output);
    if (wlOutput != nullptr && wlOutput->width > 0) {
      outputWidth =
          wlOutput->logicalWidth > 0 ? wlOutput->logicalWidth : wlOutput->width / std::max(1, wlOutput->scale);
    }
    if (wlOutput != nullptr && wlOutput->height > 0) {
      outputHeight =
          wlOutput->logicalHeight > 0 ? wlOutput->logicalHeight : wlOutput->height / std::max(1, wlOutput->scale);
    }
  }

  const auto clampMargin = [](float desired, std::int32_t panelSize, std::int32_t outputSize,
                              std::int32_t padding) -> std::int32_t {
    const std::int32_t maxValue = std::max(padding, outputSize - panelSize - padding);
    return static_cast<std::int32_t>(std::clamp(desired, static_cast<float>(padding), static_cast<float>(maxValue)));
  };

  const bool centeredH = m_activePanel->centeredHorizontally();
  const bool centeredV = m_activePanel->centeredVertically();
  const std::uint32_t anchor = centeredH  ? (isBottom ? LayerShellAnchor::Bottom : LayerShellAnchor::Top)
                               : isBottom ? LayerShellAnchor::Bottom | LayerShellAnchor::Left
                               : isLeft   ? LayerShellAnchor::Left | LayerShellAnchor::Top
                               : isRight  ? LayerShellAnchor::Right | LayerShellAnchor::Top
                                          : LayerShellAnchor::Top | LayerShellAnchor::Left;
  const std::int32_t barOffset =
      barConfig.thickness + (isVertical ? std::max(0, barConfig.marginH) : std::max(0, barConfig.marginV)) + panelGap;

  const auto marginLeft = centeredH ? 0
                                    : clampMargin(anchorX - static_cast<float>(panelWidth) * 0.5f,
                                                  static_cast<std::int32_t>(panelWidth), outputWidth, screenPadding);
  const auto marginTop = clampMargin(anchorY - static_cast<float>(panelHeight) * 0.5f,
                                     static_cast<std::int32_t>(panelHeight), outputHeight, screenPadding);

  auto surfaceConfig = LayerSurfaceConfig{
      .nameSpace = "noctalia-panel",
      .layer = m_activePanel->layer(),
      .anchor = anchor,
      .width = panelWidth,
      .height = panelHeight,
      .exclusiveZone = 0,
      .marginTop = centeredV   ? static_cast<std::int32_t>((outputHeight - static_cast<std::int32_t>(panelHeight)) / 2)
                   : centeredH ? (isBottom ? 0 : barOffset)
                   : (isLeft || isRight) ? marginTop
                                         : (isBottom ? 0 : barOffset),
      .marginRight = isRight ? barOffset : 0,
      .marginBottom = isBottom ? barOffset : 0,
      .marginLeft = centeredH ? 0 : (isLeft ? barOffset : marginLeft),
      .keyboard = m_activePanel->keyboardMode(),
      .defaultWidth = panelWidth,
      .defaultHeight = panelHeight,
  };

  const auto configureSurfaceCallbacks = [this](Surface& surface) {
    surface.setConfigureCallback([this](std::uint32_t /*width*/, std::uint32_t /*height*/) {
      if (m_surface != nullptr) {
        m_surface->requestLayout();
      }
    });
    surface.setPrepareFrameCallback(
        [this](bool needsUpdate, bool needsLayout) { prepareFrame(needsUpdate, needsLayout); });
    surface.setFrameTickCallback([this](float deltaMs) {
      if (m_activePanel != nullptr) {
        m_activePanel->onFrameTick(deltaMs);
      }
    });
    surface.setAnimationManager(&m_animations);
    surface.setRenderContext(m_renderContext);
  };

  const auto resetPanelOpenState = [this]() {
    m_surface.reset();
    m_layerSurface = nullptr;
    m_output = nullptr;
    m_wlSurface = nullptr;
    m_attachedParentSurface = nullptr;
    m_activePanel = nullptr;
    m_activePanelId.clear();
    m_pendingOpenContext.clear();
    m_panelInsetX = 0;
    m_panelInsetY = 0;
    m_panelVisualWidth = 0;
    m_panelVisualHeight = 0;
    m_attachedBackgroundOpacity = 1.0f;
    m_attachedRevealProgress = 1.0f;
    m_attachedRevealDirection = AttachedRevealDirection::Down;
    m_attachedBarPosition.clear();
    m_attachedPanelGeometry.reset();
    m_attachedToBar = false;
  };

  if (m_activePanel->prefersAttachedToBar() && m_attachedPanelParentResolver) {
    const auto parentContext = m_attachedPanelParentResolver(output, m_activePanel->preferredAttachedBarPosition());
    if (parentContext.has_value() && parentContext->parentSurface != nullptr && parentContext->barWidth > 0 &&
        parentContext->barHeight > 0) {
      const std::string_view barPosition = parentContext->barPosition;
      const bool barIsBottom = barPosition == "bottom";
      const bool barIsLeft = barPosition == "left";
      const bool barIsRight = barPosition == "right";
      const bool barIsVertical = barIsLeft || barIsRight;

      const float scale = m_activePanel->contentScale();
      const float cornerRadius = Style::radiusXl * scale;
      const auto& shadowConfig = m_config->config().shell.shadow;
      const auto shadowBleed = shell::surface_shadow::bleed(true, shadowConfig);
      const auto cornerOutset = static_cast<std::int32_t>(std::ceil(cornerRadius));

      // Cross-axis outset wraps the concave-corner overhang and shadow bleed on both
      // sides perpendicular to the bar's main axis. Main-axis bleed extends only away
      // from the bar (panel grows out from the bar edge).
      std::int32_t crossOutsetStart = 0;
      std::int32_t crossOutsetEnd = 0;
      std::int32_t mainBleedAway = 0;
      if (barIsVertical) {
        crossOutsetStart = std::max(shadowBleed.up, shadowBleed.down) + cornerOutset + 2;
        crossOutsetEnd = crossOutsetStart;
        mainBleedAway = (barIsLeft ? shadowBleed.right : shadowBleed.left) + 2;
      } else {
        crossOutsetStart = std::max(shadowBleed.left, shadowBleed.right) + cornerOutset + 2;
        crossOutsetEnd = crossOutsetStart;
        mainBleedAway = (barIsBottom ? shadowBleed.up : shadowBleed.down) + 2;
      }

      const auto crossPad = static_cast<std::uint32_t>(std::max(0, crossOutsetStart + crossOutsetEnd));
      const auto mainPad = static_cast<std::uint32_t>(std::max(0, mainBleedAway));
      const std::uint32_t surfaceWidth = barIsVertical ? (panelWidth + mainPad) : (panelWidth + crossPad);
      const std::uint32_t surfaceHeight = barIsVertical ? (panelHeight + crossPad) : (panelHeight + mainPad);

      // visualX/Y is where the panel's body (content rect) sits in parent-surface coords.
      std::int32_t visualX = 0;
      std::int32_t visualY = 0;
      if (barIsVertical) {
        const auto centeredY =
            parentContext->barY +
            static_cast<std::int32_t>(
                std::lround((static_cast<float>(parentContext->barHeight) - static_cast<float>(panelHeight)) * 0.5f));
        visualY = centeredY;
        if (barIsLeft) {
          visualX = parentContext->barX + parentContext->barWidth - kAttachedPanelBarOverlap;
        } else { // right
          visualX = parentContext->barX - static_cast<std::int32_t>(panelWidth) + kAttachedPanelBarOverlap;
        }
      } else {
        const auto centeredX =
            parentContext->barX +
            static_cast<std::int32_t>(
                std::lround((static_cast<float>(parentContext->barWidth) - static_cast<float>(panelWidth)) * 0.5f));
        visualX = centeredX;
        if (barIsBottom) {
          visualY = parentContext->barY - static_cast<std::int32_t>(panelHeight) + kAttachedPanelBarOverlap;
        } else { // top
          visualY = parentContext->barY + parentContext->barHeight - kAttachedPanelBarOverlap;
        }
      }

      // Subsurface origin sits crossOutset away from the visual rect on each cross-axis side,
      // and the main-axis bleed sits on the side opposite the bar.
      std::int32_t surfaceX = 0;
      std::int32_t surfaceY = 0;
      if (barIsVertical) {
        surfaceY = visualY - crossOutsetStart;
        surfaceX = barIsLeft ? visualX : visualX - mainBleedAway;
      } else {
        surfaceX = visualX - crossOutsetStart;
        surfaceY = barIsBottom ? visualY - mainBleedAway : visualY;
      }

      m_panelInsetX = visualX - surfaceX;
      m_panelInsetY = visualY - surfaceY;
      m_panelVisualWidth = panelWidth;
      m_panelVisualHeight = panelHeight;
      m_attachedBackgroundOpacity = resolvePanelBarConfig(m_config, m_wayland, parentContext->output).backgroundOpacity;
      m_attachedRevealProgress = 0.0f;
      m_attachedRevealDirection = attached_panel::revealDirection(barPosition);
      m_attachedBarPosition = std::string(barPosition);
      m_attachedToBar = true;
      m_layerSurface = nullptr;

      // Geometry passed to the bar for shadow exclusion. The visible rect extends past
      // the body by `cornerRadius` along the cross axis to cover the concave-corner notches.
      AttachedPanelGeometry attachedGeometry;
      attachedGeometry.cornerRadius = cornerRadius;
      if (barIsVertical) {
        attachedGeometry.x = static_cast<float>(visualX);
        attachedGeometry.y = static_cast<float>(visualY) - cornerRadius;
        attachedGeometry.width = static_cast<float>(panelWidth);
        attachedGeometry.height = static_cast<float>(panelHeight) + cornerRadius * 2.0f;
      } else {
        attachedGeometry.x = static_cast<float>(visualX) - cornerRadius;
        attachedGeometry.y = static_cast<float>(visualY);
        attachedGeometry.width = static_cast<float>(panelWidth) + cornerRadius * 2.0f;
        attachedGeometry.height = static_cast<float>(panelHeight);
      }
      m_attachedPanelGeometry = attachedGeometry;

      auto subsurface = std::make_unique<Subsurface>(*m_wayland, SubsurfaceConfig{
                                                                     .width = surfaceWidth,
                                                                     .height = surfaceHeight,
                                                                     .x = surfaceX,
                                                                     .y = surfaceY,
                                                                     .stacking = SubsurfaceStacking::BelowParent,
                                                                     .desynchronized = true,
                                                                 });
      auto* rawSubsurface = subsurface.get();
      m_surface = std::move(subsurface);
      configureSurfaceCallbacks(*m_surface);

      m_inTransition = true;
      const bool ok = rawSubsurface->initialize(parentContext->parentSurface, parentContext->output);
      m_inTransition = false;

      if (ok) {
        m_output = parentContext->output;
        m_wlSurface = m_surface->wlSurface();
        m_attachedParentSurface = parentContext->parentSurface;
        m_surface->setInputRegion(
            {InputRect{m_panelInsetX, m_panelInsetY, static_cast<int>(panelWidth), static_cast<int>(panelHeight)}});
        publishAttachedPanelGeometry(m_attachedRevealProgress);
        if (m_beginAttachedKeyboard) {
          m_beginAttachedKeyboard(parentContext->output);
        }
        m_surface->requestRedraw();
        kLog.debug("panel manager: opened \"{}\" as attached subsurface", panelId);
        return;
      }

      if (m_attachedPanelGeometryCallback) {
        m_attachedPanelGeometryCallback(parentContext->output, std::nullopt);
      }
      m_surface.reset();
      m_attachedToBar = false;
      m_panelInsetX = 0;
      m_panelInsetY = 0;
      m_panelVisualWidth = 0;
      m_panelVisualHeight = 0;
      m_attachedBackgroundOpacity = 1.0f;
      m_attachedRevealProgress = 1.0f;
      m_attachedRevealDirection = AttachedRevealDirection::Down;
      m_attachedBarPosition.clear();
      m_attachedPanelGeometry.reset();
      kLog.warn("panel manager: attached subsurface failed for \"{}\", falling back to layer-shell", panelId);
    }
  }

  auto layerSurface = std::make_unique<LayerSurface>(*m_wayland, std::move(surfaceConfig));
  m_layerSurface = layerSurface.get();
  m_surface = std::move(layerSurface);
  m_panelInsetX = 0;
  m_panelInsetY = 0;
  m_panelVisualWidth = panelWidth;
  m_panelVisualHeight = panelHeight;
  m_attachedBackgroundOpacity = 1.0f;
  m_attachedRevealProgress = 1.0f;
  m_attachedRevealDirection = AttachedRevealDirection::Down;
  m_attachedPanelGeometry.reset();
  m_attachedToBar = false;
  configureSurfaceCallbacks(*m_surface);

  // Guard against re-entrancy: initialize can process queued Wayland events,
  // re-entering our event handler before the panel is fully open.
  m_inTransition = true;
  bool ok = m_layerSurface->initialize(output);
  m_inTransition = false;

  if (!ok) {
    kLog.warn("panel manager: failed to initialize surface for panel \"{}\"", panelId);
    resetPanelOpenState();
    return;
  }

  m_output = output;
  m_wlSurface = m_surface->wlSurface();
  m_surface->setBlurRegion({});
  kLog.debug("panel manager: opened \"{}\"", panelId);
}

void PanelManager::closePanel() {
  if (!isOpen() || m_inTransition || m_closing) {
    return;
  }

  kLog.debug("panel manager: closing \"{}\"", m_activePanelId);

  // Disable input during close animation
  m_inputDispatcher.setSceneRoot(nullptr);
  m_closing = true;

  if (m_sceneRoot != nullptr) {
    const std::uint64_t gen = ++m_destroyGeneration;
    if (m_attachedToBar && m_attachedRevealClipNode != nullptr) {
      m_animations.cancelForOwner(m_attachedRevealClipNode);
      m_animations.animate(
          m_attachedRevealProgress, 0.0f, Style::animFast, Easing::EaseInOutQuad,
          [this](float v) { applyAttachedReveal(v); },
          [this, gen]() {
            DeferredCall::callLater([this, gen]() {
              if (m_destroyGeneration == gen) {
                destroyPanel();
              }
            });
          },
          m_attachedRevealClipNode);
    } else {
      m_animations.cancelForOwner(m_sceneRoot.get());
      const float startY = m_sceneRoot->y();
      m_animations.animate(
          1.0f, 0.0f, Style::animFast, Easing::EaseInOutQuad,
          [this, startY](float v) {
            m_sceneRoot->setOpacity(v);
            m_sceneRoot->setPosition(m_sceneRoot->x(), startY + (1.0f - v) * 4.0f);
          },
          [this, gen]() {
            DeferredCall::callLater([this, gen]() {
              if (m_destroyGeneration == gen) {
                destroyPanel();
              }
            });
          },
          m_sceneRoot.get());
    }
    m_surface->requestRedraw();
  } else {
    destroyPanel();
  }
}

void PanelManager::destroyPanel() {
  if (m_attachedToBar && m_attachedPanelGeometryCallback && m_output != nullptr) {
    m_attachedPanelGeometryCallback(m_output, std::nullopt);
  }
  if (m_attachedToBar && m_endAttachedKeyboard && m_output != nullptr) {
    m_endAttachedKeyboard(m_output);
  }
  m_animations.cancelAll();
  m_closing = false;
  m_pointerInside = false;
  m_attachedPopupCount = 0;
  m_inputDispatcher.setSceneRoot(nullptr);
  if (m_activePanel != nullptr) {
    m_activePanel->onClose();
  }
  m_bgNode = nullptr;
  m_contentNode = nullptr;
  m_attachedRevealClipNode = nullptr;
  m_attachedRevealContentNode = nullptr;
  m_panelShadowNode = nullptr;
  m_panelContactShadowNode = nullptr;
  m_sceneRoot.reset();
  m_surface.reset();
  m_layerSurface = nullptr;
  m_output = nullptr;
  m_wlSurface = nullptr;
  m_attachedParentSurface = nullptr;
  m_activePanel = nullptr;
  m_activePanelId.clear();
  m_pendingOpenContext.clear();
  m_panelInsetX = 0;
  m_panelInsetY = 0;
  m_panelVisualWidth = 0;
  m_panelVisualHeight = 0;
  m_attachedBackgroundOpacity = 1.0f;
  m_attachedRevealProgress = 1.0f;
  m_attachedRevealDirection = AttachedRevealDirection::Down;
  m_attachedBarPosition.clear();
  m_attachedPanelGeometry.reset();
  m_attachedToBar = false;
  if (m_wayland != nullptr) {
    m_wayland->stopKeyRepeat();
  }
}

void PanelManager::togglePanel(const std::string& panelId, wl_output* output, float anchorX, float anchorY,
                               std::string_view context) {
  // Treat a closing panel as closed: re-clicking while it animates out reopens it immediately.
  if (isOpen() && !m_closing && m_activePanelId == panelId) {
    if (!context.empty() && m_activePanel != nullptr) {
      m_activePanel->onOpen(context);
      refresh();
      return;
    }
    closePanel();
  } else {
    openPanel(panelId, output, anchorX, anchorY, context);
  }
}

void PanelManager::togglePanel(const std::string& panelId) {
  if (isOpen() && !m_closing && m_activePanelId == panelId) {
    closePanel();
    return;
  }
  wl_output* output = m_wayland != nullptr ? m_wayland->preferredPanelOutput(std::chrono::milliseconds(1200)) : nullptr;
  openPanel(panelId, output, 0.0f, 0.0f);
}

bool PanelManager::onPointerEvent(const PointerEvent& event) {
  if (!isOpen() || m_inTransition) {
    return false;
  }

  if (m_attachedPopupCount > 0) {
    if (event.surface == m_wlSurface) {
      if (event.type == PointerEvent::Type::Enter) {
        m_pointerInside = true;
      } else if (event.type == PointerEvent::Type::Leave) {
        m_pointerInside = false;
      }
    }
    return false;
  }

  switch (event.type) {
  case PointerEvent::Type::Enter: {
    if (event.surface == m_wlSurface) {
      m_pointerInside = true;
      m_inputDispatcher.pointerEnter(static_cast<float>(event.sx), static_cast<float>(event.sy), event.serial);
    }
    break;
  }
  case PointerEvent::Type::Leave: {
    if (event.surface == m_wlSurface) {
      m_pointerInside = false;
      m_inputDispatcher.pointerLeave();
    }
    break;
  }
  case PointerEvent::Type::Motion: {
    if (!m_pointerInside) {
      return false;
    }
    m_inputDispatcher.pointerMotion(static_cast<float>(event.sx), static_cast<float>(event.sy), 0);
    break;
  }
  case PointerEvent::Type::Button: {
    bool pressed = (event.state == 1);

    // Click outside panel → close
    if (pressed && !m_pointerInside) {
      closePanel();
      return false;
    }

    if (m_pointerInside) {
      if (pressed) {
        Select::handleGlobalPointerPress(m_inputDispatcher.hoveredArea());
      }
      m_inputDispatcher.pointerButton(static_cast<float>(event.sx), static_cast<float>(event.sy), event.button,
                                      pressed);
    }
    break;
  }
  case PointerEvent::Type::Axis: {
    if (!m_pointerInside) {
      return false;
    }
    m_inputDispatcher.pointerAxis(static_cast<float>(event.sx), static_cast<float>(event.sy), event.axis,
                                  event.axisSource, event.axisValue, event.axisDiscrete, event.axisValue120,
                                  event.axisLines);
    break;
  }
  }

  // Pointer interactions often only affect visual state. Relayout only when the
  // scene explicitly accumulated layout invalidation.
  if (m_surface != nullptr && m_sceneRoot != nullptr && (m_sceneRoot->paintDirty() || m_sceneRoot->layoutDirty())) {
    if (m_sceneRoot->layoutDirty() && m_activePanel != nullptr && !m_activePanel->deferPointerRelayout()) {
      m_surface->requestLayout();
    } else {
      m_surface->requestRedraw();
    }
  }

  return m_pointerInside;
}

bool PanelManager::isOpen() const noexcept { return m_surface != nullptr && m_activePanel != nullptr; }

bool PanelManager::isAttachedOpen() const noexcept { return isOpen() && m_attachedToBar; }

const std::string& PanelManager::activePanelId() const noexcept { return m_activePanelId; }

void PanelManager::refresh() {
  if (!isOpen() || m_renderContext == nullptr || m_activePanel == nullptr || m_surface == nullptr) {
    return;
  }
  if (m_activePanel->deferExternalRefresh()) {
    return;
  }

  m_surface->requestUpdate();
}

void PanelManager::requestUpdateOnly() {
  if (!isOpen() || m_surface == nullptr) {
    return;
  }
  m_surface->requestUpdateOnly();
}

void PanelManager::requestLayout() {
  if (!isOpen() || m_surface == nullptr) {
    return;
  }
  m_surface->requestLayout();
}

void PanelManager::requestRedraw() {
  if (!isOpen() || m_surface == nullptr) {
    return;
  }
  m_surface->requestRedraw();
}

void PanelManager::close() { closePanel(); }

void PanelManager::beginAttachedPopup(wl_surface* surface) {
  if (surface == nullptr || surface != m_wlSurface) {
    return;
  }
  ++m_attachedPopupCount;
}

void PanelManager::endAttachedPopup(wl_surface* surface) {
  if (surface == nullptr || surface != m_wlSurface) {
    return;
  }
  if (m_attachedPopupCount > 0) {
    --m_attachedPopupCount;
  }
  if (m_wayland != nullptr) {
    m_pointerInside = (m_wayland->lastPointerSurface() == m_wlSurface);
  }
}

std::optional<LayerPopupParentContext> PanelManager::popupParentContextForSurface(wl_surface* surface) const noexcept {
  if (surface == nullptr || surface != m_wlSurface) {
    return std::nullopt;
  }
  return fallbackPopupParentContext();
}

std::optional<LayerPopupParentContext> PanelManager::fallbackPopupParentContext() const noexcept {
  if (!isOpen() || m_surface == nullptr || m_wlSurface == nullptr || m_layerSurface == nullptr) {
    return std::nullopt;
  }

  LayerPopupParentContext context;
  context.surface = m_wlSurface;
  context.layerSurface = m_layerSurface->layerSurface();
  context.output = m_output;
  context.width = m_surface->width();
  context.height = m_surface->height();
  if (context.layerSurface == nullptr || context.width == 0 || context.height == 0) {
    return std::nullopt;
  }
  return context;
}

void PanelManager::onKeyboardEvent(const KeyboardEvent& event) {
  // m_inTransition means the surface is still initializing. Keyboard events that
  // arrive during this window must be ignored because the panel is not ready for input yet.
  if (!isOpen() || m_inTransition) {
    return;
  }

  // Gate on compositor focus: route keys only when the surface owning this panel's
  // input is the one the compositor reports as keyboard-focused. For attached panels
  // that's the bar's wl_surface (subsurfaces cannot hold focus directly); for layer
  // surfaces it's the panel's own wl_surface.
  if (m_wayland != nullptr) {
    wl_surface* const focusTarget = m_attachedToBar ? m_attachedParentSurface : m_wlSurface;
    if (focusTarget == nullptr || m_wayland->lastKeyboardSurface() != focusTarget) {
      return;
    }
  }

  if (event.pressed && m_config != nullptr &&
      m_config->matchesKeybind(KeybindAction::Cancel, event.sym, event.modifiers)) {
    closePanel();
    return;
  }

  if (m_activePanel != nullptr &&
      m_activePanel->handleGlobalKey(event.sym, event.modifiers, event.pressed, event.preedit)) {
    if (m_surface != nullptr && m_sceneRoot != nullptr && (m_sceneRoot->paintDirty() || m_sceneRoot->layoutDirty())) {
      if (m_sceneRoot->layoutDirty()) {
        m_surface->requestLayout();
      } else {
        m_surface->requestRedraw();
      }
    }
    return;
  }

  m_inputDispatcher.keyEvent(event.sym, event.utf32, event.modifiers, event.pressed, event.preedit);
  if (m_surface != nullptr && m_sceneRoot != nullptr && (m_sceneRoot->paintDirty() || m_sceneRoot->layoutDirty())) {
    if (m_sceneRoot->layoutDirty()) {
      m_surface->requestLayout();
    } else {
      m_surface->requestRedraw();
    }
  }
}

void PanelManager::applyAttachedReveal(float progress) {
  m_attachedRevealProgress = std::clamp(progress, 0.0f, 1.0f);
  if (!m_attachedToBar || m_attachedRevealClipNode == nullptr || m_sceneRoot == nullptr) {
    return;
  }

  const float w = m_sceneRoot->width();
  const float h = m_sceneRoot->height();
  const float panelW = m_panelVisualWidth > 0 ? static_cast<float>(m_panelVisualWidth) : w;
  const float panelH = m_panelVisualHeight > 0 ? static_cast<float>(m_panelVisualHeight) : h;
  const float travelX = (m_attachedRevealDirection == AttachedRevealDirection::Left ||
                         m_attachedRevealDirection == AttachedRevealDirection::Right)
                            ? panelW * (1.0f - m_attachedRevealProgress)
                            : 0.0f;
  const float travelY = (m_attachedRevealDirection == AttachedRevealDirection::Up ||
                         m_attachedRevealDirection == AttachedRevealDirection::Down)
                            ? panelH * (1.0f - m_attachedRevealProgress)
                            : 0.0f;

  float contentX = 0.0f;
  float contentY = 0.0f;
  switch (m_attachedRevealDirection) {
  case AttachedRevealDirection::Down:
    contentY = -travelY;
    break;
  case AttachedRevealDirection::Up:
    contentY = travelY;
    break;
  case AttachedRevealDirection::Right:
    contentX = -travelX;
    break;
  case AttachedRevealDirection::Left:
    contentX = travelX;
    break;
  }

  m_attachedRevealClipNode->setPosition(0.0f, 0.0f);
  m_attachedRevealClipNode->setFrameSize(w, h);

  if (m_attachedRevealContentNode != nullptr) {
    m_attachedRevealContentNode->setPosition(contentX, contentY);
    m_attachedRevealContentNode->setFrameSize(w, h);
  }
  if (m_panelShadowNode != nullptr) {
    m_panelShadowNode->setOpacity(m_attachedRevealProgress);
  }

  publishAttachedPanelGeometry(m_attachedRevealProgress);
}

void PanelManager::publishAttachedPanelGeometry(float revealProgress) {
  if (!m_attachedToBar || !m_attachedPanelGeometryCallback || m_output == nullptr || !m_attachedPanelGeometry) {
    return;
  }

  const float progress = std::clamp(revealProgress, 0.0f, 1.0f);
  if (progress <= 0.001f) {
    m_attachedPanelGeometryCallback(m_output, std::nullopt);
    return;
  }

  auto geometry = *m_attachedPanelGeometry;
  switch (m_attachedRevealDirection) {
  case AttachedRevealDirection::Down:
    geometry.height *= progress;
    break;
  case AttachedRevealDirection::Up: {
    const float visible = geometry.height * progress;
    geometry.y += geometry.height - visible;
    geometry.height = visible;
    break;
  }
  case AttachedRevealDirection::Right:
    geometry.width *= progress;
    break;
  case AttachedRevealDirection::Left: {
    const float visible = geometry.width * progress;
    geometry.x += geometry.width - visible;
    geometry.width = visible;
    break;
  }
  }

  m_attachedPanelGeometryCallback(m_output, geometry);
}

void PanelManager::buildScene(std::uint32_t width, std::uint32_t height) {
  uiAssertNotRendering("PanelManager::buildScene");
  if (m_renderContext == nullptr || m_activePanel == nullptr) {
    return;
  }
  auto* renderer = m_renderContext;
  const bool hasDecoration = m_activePanel->hasDecoration();

  const auto w = static_cast<float>(width);
  const auto h = static_cast<float>(height);

  if (m_sceneRoot == nullptr) {
    m_sceneRoot = std::make_unique<Node>();
    m_sceneRoot->setAnimationManager(&m_animations);
    m_sceneRoot->setSize(w, h);

    Node* sceneParent = m_sceneRoot.get();
    if (m_attachedToBar) {
      auto revealClip = std::make_unique<Node>();
      revealClip->setClipChildren(true);
      m_attachedRevealClipNode = m_sceneRoot->addChild(std::move(revealClip));

      auto revealContent = std::make_unique<Node>();
      m_attachedRevealContentNode = m_attachedRevealClipNode->addChild(std::move(revealContent));
      sceneParent = m_attachedRevealContentNode;
    }

    if (hasDecoration && m_attachedToBar && m_config != nullptr &&
        shell::surface_shadow::enabled(true, m_config->config().shell.shadow)) {
      auto shadow = std::make_unique<RectNode>();
      m_panelShadowNode = static_cast<RectNode*>(sceneParent->addChild(std::move(shadow)));
      m_panelShadowNode->setZIndex(-1);
    }

    if (hasDecoration) {
      auto bg = std::make_unique<Box>();
      bg->setPanelStyle();
      if (m_attachedToBar) {
        const float radius = Style::radiusXl * m_activePanel->contentScale();
        bg->setFill(roleColor(ColorRole::Surface, m_attachedBackgroundOpacity));
        bg->clearBorder();
        bg->setCornerShapes(attached_panel::cornerShapes(m_attachedBarPosition));
        bg->setLogicalInset(attached_panel::logicalInset(m_attachedBarPosition, radius));
        bg->setRadii(Radii{radius, radius, radius, radius});
      }
      m_bgNode = sceneParent->addChild(std::move(bg));
    }

    if (hasDecoration && m_attachedToBar) {
      auto contactShadow = std::make_unique<RectNode>();
      m_panelContactShadowNode = static_cast<RectNode*>(sceneParent->addChild(std::move(contactShadow)));
    }

    // Create panel content inside a wrapper node for staggered fade-in
    auto contentWrapper = std::make_unique<Node>();
    m_contentNode = contentWrapper.get();
    m_activePanel->setAnimationManager(&m_animations);
    m_activePanel->create();
    m_activePanel->onOpen(m_pendingOpenContext);
    m_pendingOpenContext.clear();
    if (m_activePanel->root() != nullptr) {
      contentWrapper->addChild(m_activePanel->releaseRoot());
    }
    sceneParent->addChild(std::move(contentWrapper));

    m_inputDispatcher.setSceneRoot(m_sceneRoot.get());
    m_inputDispatcher.setCursorShapeCallback(
        [this](std::uint32_t serial, std::uint32_t shape) { m_wayland->setCursorShape(serial, shape); });

    if (m_attachedToBar && m_attachedRevealClipNode != nullptr) {
      m_sceneRoot->setOpacity(1.0f);
      applyAttachedReveal(0.0f);
      m_animations.animate(
          0.0f, 1.0f, Style::animNormal, Easing::EaseOutCubic, [this](float v) { applyAttachedReveal(v); }, {},
          m_attachedRevealClipNode);
    } else {
      // Open animation: fast fade-in with the background growing from center.
      m_sceneRoot->setOpacity(0.0f);

      m_animations.animate(
          0.0f, 1.0f, Style::animNormal, Easing::EaseOutCubic,
          [this, w, h](float v) {
            m_sceneRoot->setOpacity(v);

            if (m_bgNode != nullptr) {
              const float attachedRadius = (m_attachedToBar && m_activePanel != nullptr)
                                               ? Style::radiusXl * m_activePanel->contentScale()
                                               : 0.0f;
              const float bodyW = m_panelVisualWidth > 0 ? static_cast<float>(m_panelVisualWidth) : w;
              const float visualW = bodyW + attachedRadius * 2.0f;
              const float visualH = m_panelVisualHeight > 0 ? static_cast<float>(m_panelVisualHeight) : h;
              const float visualX = static_cast<float>(m_panelInsetX) - attachedRadius;
              const float s = 1.0f - 0.05f * (1.0f - v);
              const float bw = visualW * s;
              const float bh = visualH * s;
              m_bgNode->setSize(bw, bh);
              m_bgNode->setPosition(visualX + (visualW - bw) * 0.5f,
                                    static_cast<float>(m_panelInsetY) + (visualH - bh) * 0.5f);
            }
          },
          {}, m_sceneRoot.get());
    }

    m_surface->setSceneRoot(m_sceneRoot.get());

    // Set initial keyboard focus if the panel requests it
    if (m_activePanel != nullptr) {
      if (auto* focusArea = m_activePanel->initialFocusArea(); focusArea != nullptr) {
        m_inputDispatcher.setFocus(focusArea);
      }
    }
  }

  m_sceneRoot->setSize(w, h);
  if (m_attachedRevealContentNode != nullptr) {
    m_attachedRevealContentNode->setFrameSize(w, h);
  }
  applyAttachedReveal(m_attachedRevealProgress);

  const float panelX = static_cast<float>(m_panelInsetX);
  const float panelY = static_cast<float>(m_panelInsetY);
  const float panelW = m_panelVisualWidth > 0 ? static_cast<float>(m_panelVisualWidth) : w;
  const float panelH = m_panelVisualHeight > 0 ? static_cast<float>(m_panelVisualHeight) : h;
  const float attachedRadius = m_attachedToBar ? Style::radiusXl * m_activePanel->contentScale() : 0.0f;
  const bool barIsVertical = m_attachedToBar && (m_attachedBarPosition == "left" || m_attachedBarPosition == "right");
  // The bg extends past the body along the bar's CROSS axis to host the concave-corner notches.
  const float bgX = barIsVertical ? panelX : panelX - attachedRadius;
  const float bgY = barIsVertical ? panelY - attachedRadius : panelY;
  const float bgW = barIsVertical ? panelW : panelW + attachedRadius * 2.0f;
  const float bgH = barIsVertical ? panelH + attachedRadius * 2.0f : panelH;

  if (m_panelShadowNode != nullptr) {
    const float scale = m_activePanel->contentScale();
    const float radius = Style::radiusXl * scale;
    const auto& shadowConfig = m_config->config().shell.shadow;
    const float shadowOffsetX = static_cast<float>(shadowConfig.offsetX);
    const float shadowOffsetY = static_cast<float>(shadowConfig.offsetY);
    const RoundedRectStyle shadowStyle =
        shell::surface_shadow::style(shadowConfig, m_attachedBackgroundOpacity,
                                     shell::surface_shadow::Shape{
                                         .corners = attached_panel::cornerShapes(m_attachedBarPosition),
                                         .logicalInset = attached_panel::logicalInset(m_attachedBarPosition, radius),
                                         .radius = Radii{radius, radius, radius, radius},
                                     });
    m_panelShadowNode->setStyle(shadowStyle);
    m_panelShadowNode->setPosition(bgX + shadowOffsetX, bgY + shadowOffsetY);
    m_panelShadowNode->setSize(bgW, bgH);
  }

  if (m_bgNode != nullptr) {
    m_bgNode->setPosition(bgX, bgY);
    m_bgNode->setSize(bgW, bgH);
  }

  if (m_panelContactShadowNode != nullptr) {
    constexpr float kContactShadowBaseThickness = 16.0f;
    const float scale = m_activePanel->contentScale();
    const float contactThickness =
        std::min(std::max(kContactShadowBaseThickness * scale, attachedRadius * 2.0f), barIsVertical ? panelW : panelH);
    const float contactAlpha = 0.16f * std::clamp(m_attachedBackgroundOpacity, 0.0f, 1.0f);
    // Gradient runs perpendicular to the bar edge, dark next to the bar, transparent toward the panel interior.
    const bool barIsBottom = m_attachedBarPosition == "bottom";
    const bool barIsRight = m_attachedBarPosition == "right";
    const bool darkAtStart = !(barIsBottom || barIsRight);
    const RoundedRectStyle contactStyle{
        .fill = darkAtStart ? rgba(0.0f, 0.0f, 0.0f, contactAlpha) : rgba(0.0f, 0.0f, 0.0f, 0.0f),
        .fillEnd = darkAtStart ? rgba(0.0f, 0.0f, 0.0f, 0.0f) : rgba(0.0f, 0.0f, 0.0f, contactAlpha),
        .border = clearColor(),
        .fillMode = FillMode::LinearGradient,
        .gradientDirection = barIsVertical ? GradientDirection::Horizontal : GradientDirection::Vertical,
        .corners = attached_panel::cornerShapes(m_attachedBarPosition),
        .logicalInset = attached_panel::logicalInset(m_attachedBarPosition, attachedRadius),
        .radius = attached_panel::cornerRadii(m_attachedBarPosition, attachedRadius),
        .softness = 1.0f,
        .borderWidth = 0.0f,
    };
    float contactX = bgX;
    float contactY = bgY;
    float contactW = bgW;
    float contactH = bgH;
    if (barIsVertical) {
      contactW = contactThickness;
      if (barIsRight) {
        contactX = bgX + bgW - contactThickness;
      }
    } else {
      contactH = contactThickness;
      if (barIsBottom) {
        contactY = bgY + bgH - contactThickness;
      }
    }
    m_panelContactShadowNode->setStyle(contactStyle);
    m_panelContactShadowNode->setPosition(contactX, contactY);
    m_panelContactShadowNode->setSize(contactW, contactH);
  }

  const float kPadding = hasDecoration ? m_activePanel->contentScale() * 12.0f : 0.0f;
  m_contentWidth = panelW - kPadding * 2.0f;
  m_contentHeight = panelH - kPadding * 2.0f;
  {
    UiPhaseScope updatePhase(UiPhase::Update);
    m_activePanel->update(*renderer);
  }
  {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    m_activePanel->layout(*renderer, m_contentWidth, m_contentHeight);
  }
  if (m_contentNode != nullptr) {
    m_contentNode->setPosition(panelX + kPadding, panelY + kPadding);
    m_contentNode->setSize(panelW - kPadding * 2.0f, panelH - kPadding * 2.0f);
  }
}

void PanelManager::prepareFrame(bool needsUpdate, bool needsLayout) {
  if (m_renderContext == nullptr || m_surface == nullptr) {
    return;
  }
  if (m_activePanel == nullptr) {
    return;
  }

  m_renderContext->makeCurrent(m_surface->renderTarget());
  m_renderContext->syncContentScale(m_surface->renderTarget());

  const auto width = m_surface->width();
  const auto height = m_surface->height();

  const bool needsSceneBuild = m_sceneRoot == nullptr ||
                               static_cast<std::uint32_t>(std::round(m_sceneRoot->width())) != width ||
                               static_cast<std::uint32_t>(std::round(m_sceneRoot->height())) != height;
  if (needsSceneBuild) {
    buildScene(width, height);
  }

  if (needsUpdate) {
    UiPhaseScope updatePhase(UiPhase::Update);
    m_activePanel->update(*m_renderContext);
  }
  if (needsLayout) {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    if (m_activePanel != nullptr) {
      m_activePanel->layout(*m_renderContext, m_contentWidth, m_contentHeight);
    }
  }
}

void PanelManager::registerIpc(IpcService& ipc) {
  ipc.registerHandler(
      "panel-toggle",
      [this](const std::string& args) -> std::string {
        if (args.empty()) {
          return "error: panel-toggle requires a panel id\n";
        }
        const auto sep = args.find(' ');
        if (sep == std::string::npos) {
          togglePanel(args);
        } else {
          const std::string panelId = args.substr(0, sep);
          if (isOpen() && !m_closing && m_activePanelId == panelId) {
            closePanel();
          } else {
            const std::string_view context = std::string_view(args).substr(sep + 1);
            wl_output* output =
                m_wayland != nullptr ? m_wayland->preferredPanelOutput(std::chrono::milliseconds(1200)) : nullptr;
            openPanel(panelId, output, 0.0f, 0.0f, context);
          }
        }
        return "ok\n";
      },
      "panel-toggle <id> [context]", "Toggle a panel by id, optionally with context (e.g. launcher /emo)");
}
