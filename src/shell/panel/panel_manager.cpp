#include "shell/panel/panel_manager.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "render/render_context.h"
#include "ui/controls/box.h"
#include "ui/controls/select.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/wayland_connection.h"
#include "wayland/wayland_seat.h"

#include <algorithm>
#include <xkbcommon/xkbcommon-keysyms.h>

PanelManager* PanelManager::s_instance = nullptr;

namespace {

constexpr Logger kLog("panel");

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
      outputWidth = wlOutput->logicalWidth > 0 ? wlOutput->logicalWidth : wlOutput->width / std::max(1, wlOutput->scale);
    }
    if (wlOutput != nullptr && wlOutput->height > 0) {
      outputHeight = wlOutput->logicalHeight > 0 ? wlOutput->logicalHeight : wlOutput->height / std::max(1, wlOutput->scale);
    }
  }

  const auto clampMargin = [](float desired, std::int32_t panelSize, std::int32_t outputSize,
                              std::int32_t padding) -> std::int32_t {
    const std::int32_t maxValue = std::max(padding, outputSize - panelSize - padding);
    return static_cast<std::int32_t>(
        std::clamp(desired, static_cast<float>(padding), static_cast<float>(maxValue)));
  };

  const bool centeredH = m_activePanel->centeredHorizontally();
  const bool centeredV = m_activePanel->centeredVertically();
  const std::uint32_t anchor = centeredH
                                   ? (isBottom ? LayerShellAnchor::Bottom : LayerShellAnchor::Top)
                               : isBottom      ? LayerShellAnchor::Bottom | LayerShellAnchor::Left
                               : isLeft        ? LayerShellAnchor::Left | LayerShellAnchor::Top
                               : isRight       ? LayerShellAnchor::Right | LayerShellAnchor::Top
                                               : LayerShellAnchor::Top | LayerShellAnchor::Left;
  const std::int32_t barOffset =
      barConfig.height + (isVertical ? std::max(0, barConfig.marginH) : std::max(0, barConfig.marginV)) + panelGap;

  const auto marginLeft = centeredH
                              ? 0
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
      .marginTop = centeredV
                       ? static_cast<std::int32_t>((outputHeight - static_cast<std::int32_t>(panelHeight)) / 2)
                   : centeredH
                       ? (isBottom ? 0 : barOffset)
                   : (isLeft || isRight) ? marginTop
                                         : (isBottom ? 0 : barOffset),
      .marginRight = isRight ? barOffset : 0,
      .marginBottom = isBottom ? barOffset : 0,
      .marginLeft = centeredH ? 0 : (isLeft ? barOffset : marginLeft),
      .keyboard = m_activePanel->keyboardMode(),
      .defaultWidth = panelWidth,
      .defaultHeight = panelHeight,
  };

  m_surface = std::make_unique<LayerSurface>(*m_wayland, std::move(surfaceConfig));
  m_surface->setConfigureCallback([this](std::uint32_t width, std::uint32_t height) { buildScene(width, height); });
  m_surface->setFrameTickCallback([this](float deltaMs) {
    if (m_activePanel != nullptr) {
      m_activePanel->onFrameTick(deltaMs);
    }
  });
  m_surface->setAnimationManager(&m_animations);
  m_surface->setRenderContext(m_renderContext);

  // Guard against re-entrancy: initialize() calls wl_display_roundtrip()
  // which can process queued pointer events, re-entering our event handler
  m_inTransition = true;
  bool ok = m_surface->initialize(output);
  m_inTransition = false;

  if (!ok) {
    kLog.warn("panel manager: failed to initialize surface for panel \"{}\"", panelId);
    m_surface.reset();
    m_activePanel = nullptr;
    m_activePanelId.clear();
    return;
  }

  m_wlSurface = m_surface->wlSurface();
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

  // Fade out the whole scene
  if (m_sceneRoot != nullptr) {
    const float startY = m_sceneRoot->y();
    const std::uint64_t gen = ++m_destroyGeneration;
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
        });
    m_surface->requestRedraw();
  } else {
    destroyPanel();
  }
}

void PanelManager::destroyPanel() {
  m_animations.cancelAll();
  m_closing = false;
  m_pointerInside = false;
  if (m_activePanel != nullptr) {
    m_activePanel->onClose();
  }
  m_bgNode = nullptr;
  m_contentNode = nullptr;
  m_sceneRoot.reset();
  m_surface.reset();
  m_wlSurface = nullptr;
  m_activePanel = nullptr;
  m_activePanelId.clear();
  m_wayland->stopKeyRepeat();
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

  // Trigger redraw if scene changed
  if (m_surface != nullptr && m_sceneRoot != nullptr && m_sceneRoot->dirty()) {
    if (m_renderContext != nullptr && m_activePanel != nullptr && !m_activePanel->deferPointerRelayout()) {
      m_activePanel->layout(*m_renderContext, m_contentWidth, m_contentHeight);
    }
    m_surface->requestRedraw();
  }

  return m_pointerInside;
}

bool PanelManager::isOpen() const noexcept { return m_surface != nullptr && m_activePanel != nullptr; }

const std::string& PanelManager::activePanelId() const noexcept { return m_activePanelId; }

void PanelManager::refresh() {
  if (!isOpen() || m_renderContext == nullptr || m_activePanel == nullptr || m_surface == nullptr) {
    return;
  }
  if (m_activePanel->deferExternalRefresh()) {
    return;
  }

  m_activePanel->update(*m_renderContext);
  m_activePanel->layout(*m_renderContext, m_contentWidth, m_contentHeight);
  m_surface->requestRedraw();
}

void PanelManager::requestRedraw() {
  if (!isOpen() || m_surface == nullptr) {
    return;
  }
  m_surface->requestRedraw();
}

void PanelManager::close() { closePanel(); }

void PanelManager::onKeyboardEvent(const KeyboardEvent& event) {
  // m_inTransition means wl_display_roundtrip() is running inside initialize().
  // Keyboard events that arrive during this roundtrip (e.g. a buffered Enter from
  // the lockscreen unlock) must be ignored — the panel is not ready for input yet.
  if (!isOpen() || m_inTransition) {
    return;
  }

  if (event.pressed && event.sym == XKB_KEY_Escape) {
    closePanel();
    return;
  }

  m_inputDispatcher.keyEvent(event.sym, event.utf32, event.modifiers, event.pressed, event.preedit);
  if (m_surface != nullptr && m_sceneRoot != nullptr && m_sceneRoot->dirty()) {
    if (m_renderContext != nullptr && m_activePanel != nullptr) {
      m_activePanel->layout(*m_renderContext, m_contentWidth, m_contentHeight);
    }
    m_surface->requestRedraw();
  }
}

void PanelManager::buildScene(std::uint32_t width, std::uint32_t height) {
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

    if (hasDecoration) {
      auto bg = std::make_unique<Box>();
      bg->setPanelStyle();
      m_bgNode = m_sceneRoot->addChild(std::move(bg));
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
    m_sceneRoot->addChild(std::move(contentWrapper));

    m_inputDispatcher.setSceneRoot(m_sceneRoot.get());
    m_inputDispatcher.setCursorShapeCallback(
        [this](std::uint32_t serial, std::uint32_t shape) { m_wayland->setCursorShape(serial, shape); });

    // Open animation: fast fade-in with the background growing from center
    m_sceneRoot->setOpacity(0.0f);

    m_animations.animate(0.0f, 1.0f, Style::animNormal, Easing::EaseOutCubic, [this, w, h](float v) {
      m_sceneRoot->setOpacity(v);

      if (m_bgNode != nullptr) {
        // Background grows from ~95% to 100%
        const float s = 1.0f - 0.05f * (1.0f - v);
        const float bw = w * s;
        const float bh = h * s;
        m_bgNode->setSize(bw, bh); // Surface::setSize auto-syncs internal rect
        m_bgNode->setPosition((w - bw) * 0.5f, (h - bh) * 0.5f);
      }
    });

    m_surface->setSceneRoot(m_sceneRoot.get());

    // Set initial keyboard focus if the panel requests it
    if (m_activePanel != nullptr) {
      if (auto* focusArea = m_activePanel->initialFocusArea(); focusArea != nullptr) {
        m_inputDispatcher.setFocus(focusArea);
      }
    }
  }

  m_sceneRoot->setSize(w, h);

  if (m_bgNode != nullptr) {
    m_bgNode->setPosition(0.0f, 0.0f);
    m_bgNode->setSize(w, h);
  }

  const float kPadding = hasDecoration ? m_activePanel->contentScale() * 12.0f : 0.0f;
  m_contentWidth = w - kPadding * 2.0f;
  m_contentHeight = h - kPadding * 2.0f;
  m_activePanel->update(*renderer);
  m_activePanel->layout(*renderer, m_contentWidth, m_contentHeight);
  if (m_contentNode != nullptr) {
    m_contentNode->setPosition(kPadding, kPadding);
    m_contentNode->setSize(w - kPadding * 2.0f, h - kPadding * 2.0f);
  }
}
