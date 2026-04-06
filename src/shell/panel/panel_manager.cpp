#include "shell/panel/panel_manager.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "render/render_context.h"
#include "ui/controls/box.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/wayland_connection.h"
#include "wayland/wayland_seat.h"

#include <algorithm>
#include <xkbcommon/xkbcommon-keysyms.h>

PanelManager* PanelManager::s_instance = nullptr;

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

void PanelManager::openPanel(const std::string& panelId, wl_output* output, std::int32_t scale, float anchorX) {
  if (m_inTransition) {
    return;
  }

  // If a panel is open (or closing), destroy it immediately — no close animation when switching
  if (isOpen() || m_closing) {
    m_closing = false;
    destroyPanel();
  }

  auto it = m_panels.find(panelId);
  if (it == m_panels.end()) {
    logWarn("panel manager: unknown panel \"{}\"", panelId);
    return;
  }

  m_activePanel = it->second.get();
  m_activePanelId = panelId;

  const auto panelWidth = static_cast<std::uint32_t>(m_activePanel->preferredWidth());
  const auto panelHeight = static_cast<std::uint32_t>(m_activePanel->preferredHeight());

  // Get bar height from config for margin calculation
  std::uint32_t barHeight = Style::barHeightDefault;
  if (m_config != nullptr && !m_config->config().bars.empty()) {
    barHeight = m_config->config().bars[0].height;
  }

  std::int32_t outputWidth = static_cast<std::int32_t>(panelWidth);
  if (m_wayland != nullptr) {
    const auto* wlOutput = m_wayland->findOutputByWl(output);
    if (wlOutput != nullptr && wlOutput->width > 0) {
      outputWidth = wlOutput->width;
    }
  }

  const float desiredLeft = anchorX - static_cast<float>(panelWidth) * 0.5f;
  const std::int32_t horizontalPadding = Style::spaceSm;
  const std::int32_t maxLeft = std::max(horizontalPadding, outputWidth - static_cast<std::int32_t>(panelWidth) -
                                                               horizontalPadding);
  const auto marginLeft =
      static_cast<std::int32_t>(std::clamp(desiredLeft, static_cast<float>(horizontalPadding), static_cast<float>(maxLeft)));

  auto surfaceConfig = LayerSurfaceConfig{
      .nameSpace = "noctalia-panel",
      .layer = LayerShellLayer::Top,
      .anchor = LayerShellAnchor::Top | LayerShellAnchor::Left,
      .width = panelWidth,
      .height = panelHeight,
      .exclusiveZone = 0,
      .marginTop = static_cast<std::int32_t>(barHeight) + 4,
      .marginLeft = marginLeft,
      .keyboard = LayerShellKeyboard::OnDemand,
      .defaultWidth = panelWidth,
      .defaultHeight = panelHeight,
  };

  m_surface = std::make_unique<LayerSurface>(*m_wayland, std::move(surfaceConfig));
  m_surface->setConfigureCallback([this](std::uint32_t width, std::uint32_t height) { buildScene(width, height); });
  m_surface->setAnimationManager(&m_animations);
  m_surface->setRenderContext(m_renderContext);

  // Guard against re-entrancy: initialize() calls wl_display_roundtrip()
  // which can process queued pointer events, re-entering our event handler
  m_inTransition = true;
  bool ok = m_surface->initialize(output, scale);
  m_inTransition = false;

  if (!ok) {
    logWarn("panel manager: failed to initialize surface for panel \"{}\"", panelId);
    m_surface.reset();
    m_activePanel = nullptr;
    m_activePanelId.clear();
    return;
  }

  m_wlSurface = m_surface->wlSurface();
  logDebug("panel manager: opened \"{}\"", panelId);
}

void PanelManager::closePanel() {
  if (!isOpen() || m_inTransition || m_closing) {
    return;
  }

  logDebug("panel manager: closing \"{}\"", m_activePanelId);

  // Disable input during close animation
  m_inputDispatcher.setSceneRoot(nullptr);
  m_closing = true;

  // Fade out the whole scene
  if (m_sceneRoot != nullptr) {
    const float startY = m_sceneRoot->y();
    m_animations.animate(
        1.0f, 0.0f, Style::animFast, Easing::EaseInOutQuad,
        [this, startY](float v) {
          m_sceneRoot->setOpacity(v);
          m_sceneRoot->setPosition(m_sceneRoot->x(), startY + (1.0f - v) * 4.0f);
        },
        [this]() { DeferredCall::callLater([this]() { destroyPanel(); }); });
    m_surface->requestRedraw();
  } else {
    destroyPanel();
  }
}

void PanelManager::destroyPanel() {
  m_animations.cancelAll();
  m_closing = false;
  m_pointerInside = false;
  m_bgNode = nullptr;
  m_contentNode = nullptr;
  m_sceneRoot.reset();
  m_surface.reset();
  m_wlSurface = nullptr;
  m_activePanel = nullptr;
  m_activePanelId.clear();
  m_wayland->stopKeyRepeat();
}

void PanelManager::togglePanel(const std::string& panelId, wl_output* output, std::int32_t scale, float anchorX) {
  if (isOpen() && m_activePanelId == panelId) {
    closePanel();
  } else {
    openPanel(panelId, output, scale, anchorX);
  }
}

bool PanelManager::onPointerEvent(const PointerEvent& event) {
  if (!isOpen()) {
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
                                  event.axisValue, event.axisDiscrete);
    break;
  }
  }

  // Trigger redraw if scene changed
  if (m_surface != nullptr && m_sceneRoot != nullptr && m_sceneRoot->dirty()) {
    if (m_renderContext != nullptr && m_activePanel != nullptr) {
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

  m_activePanel->update(*m_renderContext);
  m_activePanel->layout(*m_renderContext, m_contentWidth, m_contentHeight);
  m_surface->requestRedraw();
}

void PanelManager::close() { closePanel(); }

void PanelManager::onKeyboardEvent(const KeyboardEvent& event) {
  if (!isOpen()) {
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

  const auto w = static_cast<float>(width);
  const auto h = static_cast<float>(height);

  if (m_sceneRoot == nullptr) {
    m_sceneRoot = std::make_unique<Node>();
    m_sceneRoot->setAnimationManager(&m_animations);

    // Panel background
    auto bg = std::make_unique<Box>();
    bg->setPanelStyle();
    m_bgNode = m_sceneRoot->addChild(std::move(bg));

    // Create panel content inside a wrapper node for staggered fade-in
    auto contentWrapper = std::make_unique<Node>();
    m_contentNode = contentWrapper.get();
    m_activePanel->setAnimationManager(&m_animations);
    m_activePanel->create(*renderer);
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

      // Background grows from ~95% to 100%
      const float s = 1.0f - 0.05f * (1.0f - v);
      const float bw = w * s;
      const float bh = h * s;
      m_bgNode->setSize(bw, bh); // Surface::setSize auto-syncs internal rect
      m_bgNode->setPosition((w - bw) * 0.5f, (h - bh) * 0.5f);
    });

    m_surface->setSceneRoot(m_sceneRoot.get());
  }

  m_sceneRoot->setSize(w, h);

  m_bgNode->setPosition(0.0f, 0.0f);
  m_bgNode->setSize(w, h);

  // Layout panel content with padding
  constexpr float kPadding = 12.0f;
  m_contentWidth = w - kPadding * 2.0f;
  m_contentHeight = h - kPadding * 2.0f;
  m_activePanel->layout(*renderer, m_contentWidth, m_contentHeight);
  if (m_contentNode != nullptr) {
    m_contentNode->setPosition(kPadding, kPadding);
    m_contentNode->setSize(w - kPadding * 2.0f, h - kPadding * 2.0f);
  }
}
