#include "shell/PanelManager.h"

#include "config/ConfigService.h"
#include "core/Log.h"
#include "render/programs/RoundedRectProgram.h"
#include "render/scene/RectNode.h"
#include "ui/style/Palette.h"
#include "ui/style/Style.h"
#include "wayland/WaylandConnection.h"
#include "wayland/WaylandSeat.h"

#include <algorithm>

PanelManager::PanelManager() = default;

void PanelManager::initialize(WaylandConnection& wayland, ConfigService* config) {
  m_wayland = &wayland;
  m_config = config;
}

void PanelManager::setCloseCallback(CloseCallback callback) { m_closeCallback = std::move(callback); }

void PanelManager::registerPanel(const std::string& id, std::unique_ptr<PanelContent> content) {
  m_panels[id] = std::move(content);
}

void PanelManager::openPanel(const std::string& panelId, wl_output* output, std::int32_t scale, float anchorX) {
  if (m_inTransition) {
    return;
  }

  // Close any currently open panel
  if (isOpen()) {
    closePanel();
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
  std::uint32_t barHeight = 42;
  if (m_config != nullptr && !m_config->config().bars.empty()) {
    barHeight = m_config->config().bars[0].height;
  }

  // Compute right margin to position panel near the anchor point
  // Find the output width to calculate margin from right edge
  std::int32_t outputWidth = 1920;
  if (m_wayland != nullptr) {
    const auto* wlOutput = m_wayland->findOutputByWl(output);
    if (wlOutput != nullptr) {
      outputWidth = wlOutput->width;
    }
  }

  // Position: right edge of panel aligns near anchorX, clamped to screen
  auto marginRight =
      static_cast<std::int32_t>(static_cast<float>(outputWidth) - anchorX - static_cast<float>(panelWidth) * 0.5f);
  marginRight = std::max(8, marginRight);
  marginRight = std::min(marginRight, outputWidth - static_cast<std::int32_t>(panelWidth) - 8);

  auto surfaceConfig = LayerSurfaceConfig{
      .nameSpace = "noctalia-panel",
      .layer = LayerShellLayer::Top,
      .anchor = LayerShellAnchor::Top | LayerShellAnchor::Right,
      .width = panelWidth,
      .height = panelHeight,
      .exclusiveZone = 0,
      .marginTop = static_cast<std::int32_t>(barHeight) + 4,
      .marginRight = marginRight,
      .keyboard = LayerShellKeyboard::None,
      .defaultWidth = panelWidth,
      .defaultHeight = panelHeight,
  };

  m_surface = std::make_unique<LayerSurface>(*m_wayland, std::move(surfaceConfig));
  m_surface->setConfigureCallback([this](std::uint32_t width, std::uint32_t height) { buildScene(width, height); });
  m_surface->setAnimationManager(&m_animations);

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
  logInfo("panel manager: opened \"{}\"", panelId);
}

void PanelManager::closePanel() {
  if (!isOpen() || m_inTransition) {
    return;
  }

  logInfo("panel manager: closed \"{}\"", m_activePanelId);

  m_inputDispatcher.setSceneRoot(nullptr);
  m_pointerInside = false;
  m_sceneRoot.reset();
  m_surface.reset();
  m_wlSurface = nullptr;
  m_activePanel = nullptr;
  m_activePanelId.clear();

  if (m_closeCallback) {
    m_closeCallback();
  }
}

void PanelManager::togglePanel(const std::string& panelId, wl_output* output, std::int32_t scale, float anchorX) {
  if (isOpen() && m_activePanelId == panelId) {
    closePanel();
  } else {
    openPanel(panelId, output, scale, anchorX);
  }
}

void PanelManager::onPointerEvent(const PointerEvent& event) {
  if (!isOpen()) {
    return;
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
      return;
    }
    m_inputDispatcher.pointerMotion(static_cast<float>(event.sx), static_cast<float>(event.sy), 0);
    break;
  }
  case PointerEvent::Type::Button: {
    bool pressed = (event.state == 1);

    // Click outside panel → close
    if (pressed && !m_pointerInside) {
      closePanel();
      return;
    }

    if (m_pointerInside) {
      m_inputDispatcher.pointerButton(static_cast<float>(event.sx), static_cast<float>(event.sy), event.button,
                                      pressed);
    }
    break;
  }
  }

  // Trigger redraw if scene changed
  if (m_surface != nullptr && m_sceneRoot != nullptr && m_sceneRoot->dirty()) {
    m_surface->requestRedraw();
  }
}

bool PanelManager::isOpen() const noexcept { return m_surface != nullptr && m_activePanel != nullptr; }

const std::string& PanelManager::activePanelId() const noexcept { return m_activePanelId; }

void PanelManager::close() { closePanel(); }

void PanelManager::buildScene(std::uint32_t width, std::uint32_t height) {
  auto* renderer = m_surface->renderer();
  if (renderer == nullptr || m_activePanel == nullptr) {
    return;
  }

  const auto w = static_cast<float>(width);
  const auto h = static_cast<float>(height);

  if (m_sceneRoot == nullptr) {
    m_sceneRoot = std::make_unique<Node>();

    // Panel background
    auto bg = std::make_unique<RectNode>();
    bg->setStyle(RoundedRectStyle{
        .fill = palette.surface,
        .border = palette.outline,
        .fillMode = FillMode::Solid,
        .radius = Style::radiusLg,
        .softness = 1.2f,
        .borderWidth = Style::borderWidth,
    });
    m_sceneRoot->addChild(std::move(bg));

    // Create panel content
    m_activePanel->setAnimationManager(&m_animations);
    m_activePanel->create(*renderer);
    if (m_activePanel->root() != nullptr) {
      m_sceneRoot->addChild(m_activePanel->releaseRoot());
    }

    m_inputDispatcher.setSceneRoot(m_sceneRoot.get());
    m_inputDispatcher.setCursorShapeCallback(
        [this](std::uint32_t serial, std::uint32_t shape) { m_wayland->setCursorShape(serial, shape); });

    renderer->setScene(m_sceneRoot.get());
    m_surface->setSceneRoot(m_sceneRoot.get());
  }

  m_sceneRoot->setSize(w, h);

  // Background rect with padding
  auto& children = m_sceneRoot->children();
  children[0]->setPosition(0.0f, 0.0f);
  children[0]->setSize(w, h);

  // Layout panel content with padding
  constexpr float kPadding = 12.0f;
  m_activePanel->layout(*renderer, w - kPadding * 2.0f, h - kPadding * 2.0f);
  if (m_activePanel->root() != nullptr) {
    m_activePanel->root()->setPosition(kPadding, kPadding);
  }
}
