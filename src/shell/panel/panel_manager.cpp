#include "shell/panel/panel_manager.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "core/ui_phase.h"
#include "ipc/ipc_service.h"
#include "render/core/renderer.h"
#include "render/render_context.h"
#include "shell/control_center/control_center_panel.h"
#include "shell/surface_shadow.h"
#include "ui/controls/box.h"
#include "ui/controls/context_menu_popup.h"
#include "ui/controls/select.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/wayland_connection.h"
#include "wayland/wayland_seat.h"

#include <algorithm>
#include <cmath>
#include <string>

PanelManager* PanelManager::s_instance = nullptr;

namespace {

  constexpr Logger kLog("panel");
  constexpr std::int32_t kAttachedPanelBarOverlap = 1;

  BarConfig resolvePanelBarConfig(ConfigService* configService, WaylandConnection* wayland, wl_output* output,
                                  std::string_view barName = {}) {
    BarConfig barConfig;
    if (configService == nullptr || configService->config().bars.empty()) {
      return barConfig;
    }

    const auto& bars = configService->config().bars;
    bool found = false;
    if (!barName.empty()) {
      for (const auto& bar : bars) {
        if (bar.name == barName) {
          barConfig = bar;
          found = true;
          break;
        }
      }
    }
    if (!found) {
      barConfig = bars.front();
    }

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
  m_clickShield.initialize(wayland);
  m_focusGrab.initialize(wayland);
  m_focusGrab.setOnCleared([this]() {
    if (isOpen() && !m_closing) {
      closePanel();
    }
  });
}

void PanelManager::setOpenSettingsWindowCallback(std::function<void()> callback) {
  m_openSettingsWindow = std::move(callback);
}

void PanelManager::openSettingsWindow() {
  if (isOpen() && !m_closing) {
    closePanel();
  }
  if (m_openSettingsWindow) {
    m_openSettingsWindow();
  }
}

void PanelManager::setAttachedPanelGeometryCallback(
    std::function<void(wl_output*, std::optional<AttachedPanelGeometry>)> callback) {
  m_attachedPanelGeometryCallback = std::move(callback);
}

void PanelManager::setClickShieldExcludeRectsProvider(std::function<std::vector<InputRect>(wl_output*)> provider) {
  m_clickShieldExcludeRectsProvider = std::move(provider);
}

void PanelManager::setFocusGrabBarSurfacesProvider(std::function<std::vector<wl_surface*>()> provider) {
  m_focusGrabBarSurfacesProvider = std::move(provider);
}

void PanelManager::registerPanel(const std::string& id, std::unique_ptr<Panel> content) {
  m_panels[id] = std::move(content);
}

void PanelManager::openPanel(const std::string& panelId, PanelOpenRequest request) {
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
  m_sourceBarName = std::string(request.sourceBarName);
  m_activePanel->setContentScale(resolvePanelContentScale(m_config));
  m_pendingOpenContext = std::string(request.context);

  // Map shields BEFORE the panel surface is created/committed. Within a
  // single layer, wlroots stacks surfaces by mapping order — the shields
  // need to be mapped first so the panel ends up on top of them.
  activateClickShield();

  const auto panelWidth = static_cast<std::uint32_t>(m_activePanel->preferredWidth());
  const auto panelHeight = static_cast<std::uint32_t>(m_activePanel->preferredHeight());
  const auto barConfig = resolvePanelBarConfig(m_config, m_wayland, request.output, request.sourceBarName);
  const bool isBottom = barConfig.position == "bottom";
  const bool isLeft = barConfig.position == "left";
  const bool isRight = barConfig.position == "right";
  const bool isVertical = isLeft || isRight;
  const std::int32_t panelGap = static_cast<std::int32_t>(Style::spaceXs);
  const std::int32_t screenPadding = static_cast<std::int32_t>(Style::spaceSm);

  std::int32_t outputWidth = static_cast<std::int32_t>(panelWidth);
  std::int32_t outputHeight = static_cast<std::int32_t>(panelHeight);
  if (m_wayland != nullptr) {
    const auto* wlOutput = m_wayland->findOutputByWl(request.output);
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
                                    : clampMargin(request.anchorX - static_cast<float>(panelWidth) * 0.5f,
                                                  static_cast<std::int32_t>(panelWidth), outputWidth, screenPadding);
  const auto marginTop = clampMargin(request.anchorY - static_cast<float>(panelHeight) * 0.5f,
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
    deactivateOutsideClickHandlers();
    m_surface.reset();
    m_layerSurface = nullptr;
    m_output = nullptr;
    m_wlSurface = nullptr;
    m_activePanel = nullptr;
    m_activePanelId.clear();
    m_pendingOpenContext.clear();
    m_panelInsetX = 0;
    m_panelInsetY = 0;
    m_panelVisualWidth = 0;
    m_panelVisualHeight = 0;
    m_attachedBackgroundOpacity = 1.0f;
    m_attachedContactShadow = false;
    m_attachedRevealProgress = 1.0f;
    m_attachedRevealDirection = AttachedRevealDirection::Down;
    m_attachedBarPosition.clear();
    m_sourceBarName.clear();
    m_attachedPanelGeometry.reset();
    m_attachedToBar = false;
  };

  if (m_activePanel->prefersAttachedToBar() && barConfig.attachPanels && barConfig.thickness > 0 && outputWidth > 0 &&
      outputHeight > 0) {
    const std::string_view barPosition = barConfig.position;
    const bool barIsBottom = barPosition == "bottom";
    const bool barIsLeft = barPosition == "left";
    const bool barIsRight = barPosition == "right";
    const bool barIsVertical = barIsLeft || barIsRight;

    const float scale = m_activePanel->contentScale();
    const float cornerRadius = Style::radiusXl * scale;
    const auto& shadowConfig = m_config->config().shell.shadow;
    const auto shadowBleed = shell::surface_shadow::bleed(true, shadowConfig);
    const auto cornerOutset = static_cast<std::int32_t>(std::ceil(cornerRadius));

    // Cross-axis outset wraps the concave-corner overhang and shadow bleed on both sides
    // perpendicular to the bar. Main-axis bleed extends only away from the bar (panel grows
    // outward from the bar edge).
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

    // Bar visible rect in screen coords, derived from BarConfig + output dimensions.
    const std::int32_t marginH = std::max(0, barConfig.marginH);
    const std::int32_t marginV = std::max(0, barConfig.marginV);
    const std::int32_t barLeft = barIsRight ? std::max(0, outputWidth - marginH - barConfig.thickness) : marginH;
    const std::int32_t barTop = barIsBottom ? std::max(0, outputHeight - marginV - barConfig.thickness) : marginV;
    const std::int32_t barRight =
        barIsVertical ? barLeft + barConfig.thickness : std::max(barLeft, outputWidth - marginH);
    const std::int32_t barBottom =
        barIsVertical ? std::max(barTop, outputHeight - marginV) : barTop + barConfig.thickness;

    // Panel body rect in screen coords. Centered on the bar's main axis; 1 px bar overlap
    // so the concave-corner notches read as merged with the bar edge.
    std::int32_t visualX = 0;
    std::int32_t visualY = 0;
    if (barIsVertical) {
      const auto centeredY = barTop + (barBottom - barTop - static_cast<std::int32_t>(panelHeight)) / 2;
      visualY = centeredY;
      visualX = barIsLeft ? barRight - kAttachedPanelBarOverlap
                          : barLeft - static_cast<std::int32_t>(panelWidth) + kAttachedPanelBarOverlap;
    } else {
      const auto centeredX = barLeft + (barRight - barLeft - static_cast<std::int32_t>(panelWidth)) / 2;
      visualX = centeredX;
      visualY = barIsBottom ? barTop - static_cast<std::int32_t>(panelHeight) + kAttachedPanelBarOverlap
                            : barBottom - kAttachedPanelBarOverlap;
    }

    // Surface origin: cross-axis outset on each side, main-axis bleed on the side opposite the bar.
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
    m_attachedBackgroundOpacity = m_activePanel->inheritsBarBackgroundOpacity()
                                      ? barConfig.backgroundOpacity
                                      : m_activePanel->attachedBackgroundOpacityOverride();
    m_attachedContactShadow = barConfig.contactShadow && barConfig.shadow;
    m_attachedRevealProgress = 0.0f;
    m_attachedRevealDirection = attached_panel::revealDirection(barPosition);
    m_attachedBarPosition = std::string(barPosition);
    m_attachedToBar = true;

    // Convert panel screen coords to bar-surface-local coords for the shadow exclusion callback.
    // Bar's surface is bigger than its visible rect (it includes shadow padding), so its origin
    // sits one shadow bleed inset from the visible bar's top-left. Mirrors the layout in
    // bar.cpp's bar surface creation (the "mLeft, mTop" anchor offsets).
    const auto barShadowBleed = shell::surface_shadow::bleed(barConfig.shadow, shadowConfig);
    std::int32_t barSurfaceLocalVisualX = visualX;
    std::int32_t barSurfaceLocalVisualY = visualY;
    if (barIsVertical) {
      barSurfaceLocalVisualY = visualY - (barTop - std::min(marginV, barShadowBleed.up));
      const std::int32_t barSurfaceOriginX =
          barIsLeft ? std::max(0, marginH - barShadowBleed.left) : barLeft - barShadowBleed.left;
      barSurfaceLocalVisualX = visualX - barSurfaceOriginX;
    } else {
      barSurfaceLocalVisualX = visualX - (barLeft - std::min(marginH, barShadowBleed.left));
      const std::int32_t barSurfaceOriginY =
          barIsBottom ? barTop - barShadowBleed.up : std::max(0, marginV - barShadowBleed.up);
      barSurfaceLocalVisualY = visualY - barSurfaceOriginY;
    }

    // Geometry passed to the bar for shadow exclusion (bar-surface-local coords). The visible
    // rect extends past the body by `cornerRadius` on the cross axis to cover concave-corner notches.
    AttachedPanelGeometry attachedGeometry;
    attachedGeometry.cornerRadius = cornerRadius;
    attachedGeometry.bulgeRadius = cornerRadius;
    if (barIsVertical) {
      attachedGeometry.x = static_cast<float>(barSurfaceLocalVisualX);
      attachedGeometry.y = static_cast<float>(barSurfaceLocalVisualY) - cornerRadius;
      attachedGeometry.width = static_cast<float>(panelWidth);
      attachedGeometry.height = static_cast<float>(panelHeight) + cornerRadius * 2.0f;
    } else {
      attachedGeometry.x = static_cast<float>(barSurfaceLocalVisualX) - cornerRadius;
      attachedGeometry.y = static_cast<float>(barSurfaceLocalVisualY);
      attachedGeometry.width = static_cast<float>(panelWidth) + cornerRadius * 2.0f;
      attachedGeometry.height = static_cast<float>(panelHeight);
    }
    m_attachedPanelGeometry = attachedGeometry;

    // Layer-shell surface anchored top-left of the output for absolute positioning. The panel
    // sits on top of the bar in stacking order; the clip-reveal animation hides any pre-reveal
    // overdraw. exclusive_zone = -1 so the bar's reservation does NOT shift our marginTop —
    // we compute marginTop directly in screen coords and want the compositor to honor it.
    auto attachedConfig = LayerSurfaceConfig{
        .nameSpace = "noctalia-panel",
        .layer = m_activePanel->layer(),
        .anchor = LayerShellAnchor::Top | LayerShellAnchor::Left,
        .width = surfaceWidth,
        .height = surfaceHeight,
        .exclusiveZone = -1,
        .marginTop = surfaceY,
        .marginRight = 0,
        .marginBottom = 0,
        .marginLeft = surfaceX,
        // Default: force exclusive keyboard so panels with text inputs (search field, etc.) work
        // without a prior click — matches the previous subsurface behavior where the bar
        // borrowed exclusive focus on the panel's behalf. On Hyprland, Exclusive on a layer
        // surface also grabs the pointer (any click anywhere reports on this surface), which
        // breaks outside-click dismissal. When the focus_grab protocol is available we drop to
        // OnDemand and let the grab grant keyboard focus to the panel per the spec.
        .keyboard = m_focusGrab.available() ? LayerShellKeyboard::OnDemand : LayerShellKeyboard::Exclusive,
        .defaultWidth = surfaceWidth,
        .defaultHeight = surfaceHeight,
    };

    auto layerSurfaceUnique = std::make_unique<LayerSurface>(*m_wayland, std::move(attachedConfig));
    m_layerSurface = layerSurfaceUnique.get();
    m_surface = std::move(layerSurfaceUnique);
    configureSurfaceCallbacks(*m_surface);

    m_inTransition = true;
    const bool ok = m_layerSurface->initialize(request.output);
    m_inTransition = false;

    if (ok) {
      m_output = request.output;
      m_wlSurface = m_surface->wlSurface();
      m_surface->setInputRegion(
          {InputRect{m_panelInsetX, m_panelInsetY, static_cast<int>(panelWidth), static_cast<int>(panelHeight)}});
      applyPanelCompositorBlur();
      publishAttachedPanelGeometry(m_attachedRevealProgress);
      m_surface->requestRedraw();
      // Defer the focus grab to the next tick: Hyprland's focus_grab seems to
      // need the whitelisted surfaces to actually be mapped, which only
      // happens after the configure round-trip completes.
      const std::uint64_t gen = m_destroyGeneration;
      DeferredCall::callLater([this, gen]() {
        if (m_destroyGeneration == gen) {
          activateFocusGrab();
        }
      });
      kLog.debug("panel manager: opened \"{}\" as attached layer-shell", panelId);
      return;
    }

    if (m_attachedPanelGeometryCallback) {
      m_attachedPanelGeometryCallback(request.output, std::nullopt);
    }
    m_surface.reset();
    m_layerSurface = nullptr;
    m_attachedToBar = false;
    m_panelInsetX = 0;
    m_panelInsetY = 0;
    m_panelVisualWidth = 0;
    m_panelVisualHeight = 0;
    m_attachedBackgroundOpacity = 1.0f;
    m_attachedContactShadow = false;
    m_attachedRevealProgress = 1.0f;
    m_attachedRevealDirection = AttachedRevealDirection::Down;
    m_attachedBarPosition.clear();
    m_attachedPanelGeometry.reset();
    kLog.warn("panel manager: attached layer-shell failed for \"{}\", falling back to standalone", panelId);
  }

  auto layerSurface = std::make_unique<LayerSurface>(*m_wayland, std::move(surfaceConfig));
  m_layerSurface = layerSurface.get();
  m_surface = std::move(layerSurface);
  m_panelInsetX = 0;
  m_panelInsetY = 0;
  m_panelVisualWidth = panelWidth;
  m_panelVisualHeight = panelHeight;
  m_attachedBackgroundOpacity = 1.0f;
  m_attachedContactShadow = false;
  m_attachedRevealProgress = 1.0f;
  m_attachedRevealDirection = AttachedRevealDirection::Down;
  m_attachedPanelGeometry.reset();
  m_attachedToBar = false;
  configureSurfaceCallbacks(*m_surface);

  // Guard against re-entrancy: initialize can process queued Wayland events,
  // re-entering our event handler before the panel is fully open.
  m_inTransition = true;
  bool ok = m_layerSurface->initialize(request.output);
  m_inTransition = false;

  if (!ok) {
    kLog.warn("panel manager: failed to initialize surface for panel \"{}\"", panelId);
    resetPanelOpenState();
    return;
  }

  m_output = request.output;
  m_wlSurface = m_surface->wlSurface();
  applyPanelCompositorBlur();
  // Defer the focus grab to the next tick — see attached-path comment above.
  const std::uint64_t gen = m_destroyGeneration;
  DeferredCall::callLater([this, gen]() {
    if (m_destroyGeneration == gen) {
      activateFocusGrab();
    }
  });
  kLog.debug("panel manager: opened \"{}\"", panelId);
}

void PanelManager::activateClickShield() {
  if (m_activePanel == nullptr || m_wayland == nullptr) {
    return;
  }
  // Hyprland: prefer the native focus-grab path; the shield can't reliably
  // exclude bar surfaces there (input region exclusion isn't honored when
  // keyboard_interactivity is Exclusive, which is what unlocks pointer
  // delivery). Skip the shield and let activateFocusGrab() handle it later.
  if (m_focusGrab.available()) {
    return;
  }
  std::vector<wl_output*> outputs;
  outputs.reserve(m_wayland->outputs().size());
  for (const auto& wlOutput : m_wayland->outputs()) {
    if (wlOutput.output != nullptr) {
      outputs.push_back(wlOutput.output);
    }
  }
  m_clickShield.activate(outputs, m_activePanel->layer(), m_clickShieldExcludeRectsProvider);
}

void PanelManager::activateFocusGrab() {
  if (!m_focusGrab.available() || m_wlSurface == nullptr) {
    return;
  }
  // Whitelist the panel + every bar surface. Clicks on whitelisted surfaces
  // pass through normally so bar widgets can toggle the next panel; clicks
  // anywhere else clear the grab and we close the panel via the `cleared`
  // event handler. The panel uses OnDemand keyboard mode on Hyprland (the
  // focus_grab grants keyboard focus to the panel on its own) so the panel
  // surface no longer grabs the pointer the way Exclusive does.
  std::vector<wl_surface*> whitelist;
  whitelist.push_back(m_wlSurface);
  if (m_focusGrabBarSurfacesProvider) {
    auto bars = m_focusGrabBarSurfacesProvider();
    whitelist.insert(whitelist.end(), bars.begin(), bars.end());
  }
  m_focusGrab.activate(whitelist);
}

void PanelManager::deactivateOutsideClickHandlers() {
  m_clickShield.deactivate();
  m_focusGrab.deactivate();
}

void PanelManager::closePanel() {
  if (!isOpen() || m_inTransition || m_closing) {
    return;
  }

  kLog.debug("panel manager: closing \"{}\"", m_activePanelId);

  // Drop the outside-click handlers as soon as close starts. During the close
  // animation we want clicks on apps to behave normally, not re-trigger close.
  deactivateOutsideClickHandlers();

  // Disable input during close animation
  m_inputDispatcher.setSceneRoot(nullptr);
  m_closing = true;

  if (m_sceneRoot != nullptr) {
    const std::uint64_t gen = ++m_destroyGeneration;
    if (m_attachedToBar && m_attachedRevealClipNode != nullptr) {
      m_animations.cancelForOwner(m_attachedRevealClipNode);
      m_animations.animate(
          m_attachedRevealProgress, 0.0f, Style::animNormal, Easing::EaseInOutQuad,
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
      m_animations.animate(
          m_detachedRevealProgress, 0.0f, Style::animFast, Easing::EaseInOutQuad,
          [this](float v) { applyDetachedReveal(v); },
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
  // Defensive: closePanel deactivates first, but destroyPanel can also be
  // reached directly (e.g. when openPanel preempts an open panel).
  deactivateOutsideClickHandlers();
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
  m_activePanel = nullptr;
  m_activePanelId.clear();
  m_pendingOpenContext.clear();
  m_panelInsetX = 0;
  m_panelInsetY = 0;
  m_panelVisualWidth = 0;
  m_panelVisualHeight = 0;
  m_attachedBackgroundOpacity = 1.0f;
  m_attachedContactShadow = false;
  m_attachedRevealProgress = 1.0f;
  m_attachedRevealDirection = AttachedRevealDirection::Down;
  m_attachedBarPosition.clear();
  m_sourceBarName.clear();
  m_attachedPanelGeometry.reset();
  m_attachedToBar = false;
  if (m_wayland != nullptr) {
    m_wayland->stopKeyRepeat();
  }
}

void PanelManager::togglePanel(const std::string& panelId, PanelOpenRequest request) {
  // Treat a closing panel as closed: re-clicking while it animates out reopens it immediately.
  if (isOpen() && !m_closing && m_activePanelId == panelId) {
    if (!request.context.empty() && m_activePanel != nullptr) {
      if (m_activePanel->isContextActive(request.context)) {
        closePanel();
        return;
      }
      m_activePanel->onOpen(request.context);
      refresh();
      return;
    }
    closePanel();
  } else {
    openPanel(panelId, request);
  }
}

void PanelManager::togglePanel(const std::string& panelId) {
  if (isOpen() && !m_closing && m_activePanelId == panelId) {
    closePanel();
    return;
  }
  wl_output* output = m_wayland != nullptr ? m_wayland->preferredPanelOutput(std::chrono::milliseconds(1200)) : nullptr;
  openPanel(panelId, PanelOpenRequest{.output = output});
}

bool PanelManager::onPointerEvent(const PointerEvent& event) {
  if (!isOpen() || m_inTransition) {
    return false;
  }

  if (m_activePopup != nullptr) {
    if (m_activePopup->onPointerEvent(event)) {
      return true;
    }
    if (event.type == PointerEvent::Type::Button && event.state == 1) {
      m_activePopup->close();
      return true;
    }
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
      if (pressed && event.surface == m_wlSurface && m_activePanelId == "control-center" &&
          m_inputDispatcher.hoveredArea() == nullptr) {
        if (auto* controlCenter = dynamic_cast<ControlCenterPanel*>(m_activePanel);
            controlCenter != nullptr && controlCenter->dismissTransientUi()) {
          refresh();
          return true;
        }
      }
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

bool PanelManager::isActivePanelContext(std::string_view context) const noexcept {
  if (!isOpen() || m_activePanel == nullptr) {
    return false;
  }
  return m_activePanel->isContextActive(context);
}

void PanelManager::refresh() {
  if (!isOpen() || m_renderContext == nullptr || m_activePanel == nullptr || m_surface == nullptr) {
    return;
  }
  if (m_activePanel->deferExternalRefresh()) {
    return;
  }

  m_surface->requestUpdate();
}

void PanelManager::onIconThemeChanged() {
  if (!isOpen() || m_activePanel == nullptr || m_surface == nullptr) {
    return;
  }

  m_activePanel->onIconThemeChanged();
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

void PanelManager::setActivePopup(ContextMenuPopup* popup) { m_activePopup = popup; }

void PanelManager::clearActivePopup() { m_activePopup = nullptr; }

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
    wl_surface* const focusTarget = m_wlSurface;
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
  if (m_panelContactShadowNode != nullptr) {
    m_panelContactShadowNode->setOpacity(m_attachedRevealProgress);
  }

  publishAttachedPanelGeometry(m_attachedRevealProgress);
  applyPanelCompositorBlur();
}

void PanelManager::applyDetachedReveal(float progress) {
  m_detachedRevealProgress = std::clamp(progress, 0.0f, 1.0f);
  if (m_attachedToBar || m_sceneRoot == nullptr) {
    return;
  }
  // Scale the entire scene (background, content, shadow) from 0.95 -> 1.0
  // around the surface center. Opacity is intentionally not animated because
  // the compositor blur region (ext-background-effect-v1) is not opacity-aware
  // and would mismatch a fading content layer.
  const float s = 1.0f - 0.05f * (1.0f - m_detachedRevealProgress);
  m_sceneRoot->setScale(s);
  // Fade only the content layer; the background must stay fully opaque so the
  // compositor blur region is always covered by an opaque rect (otherwise the
  // blur would leak through during the animation).
  if (m_contentNode != nullptr) {
    m_contentNode->setOpacity(m_detachedRevealProgress);
  }
  applyPanelCompositorBlur();
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

  // The bar-side concave bulges live at the bg's bar-side edge and only enter the
  // visible clip during the last `radius / panelMainDim` portion of the animation
  // (before that, the bg's bar-side edge is still behind the bar). Until they're
  // visible, the visible panel silhouette is a sharp-edged rectangle on the bar
  // side, so the cutout's bulge radius and per-side cross-axis extension scale up
  // linearly only as the bulges slide into view. The away-side convex corners are
  // visible throughout the animation (they're at the leading edge of the slide),
  // so cornerRadius is left at its full value — the bar uses cornerRadius for the
  // away-side corners and bulgeRadius for the bar-side corners.
  const float originalRadius = geometry.cornerRadius;
  const bool vertical = (m_attachedRevealDirection == AttachedRevealDirection::Right ||
                         m_attachedRevealDirection == AttachedRevealDirection::Left);
  const float panelMainDim = vertical ? geometry.width : geometry.height;
  const float bulgeRevealAmount = std::clamp(originalRadius - panelMainDim * (1.0f - progress), 0.0f, originalRadius);
  const float crossDelta = originalRadius - bulgeRevealAmount;
  geometry.bulgeRadius = bulgeRevealAmount;

  // The away-side convex corners are visible at full radius throughout the animation
  // (they're at the leading edge of the slide). The rect shader clamps each corner's
  // radius to min(body_w, body_h)/2 — so when the visible body is shorter than
  // 2*cornerRadius along the main axis, the convex corners would shrink and shift
  // inward, no longer matching the visible bg's curve. Extend the body main-axis
  // dimension toward the bar so it's at least 2*cornerRadius. The extension goes
  // BAR-WARD into the bar's body area, where the bar covers the cutout's effect on
  // the shadow underneath (and the cutout's straight bar-side edge stays hidden).
  const float minMainDim = 2.0f * originalRadius;

  switch (m_attachedRevealDirection) {
  case AttachedRevealDirection::Down: {
    const float visibleHeight = geometry.height * progress;
    const float effectiveHeight = std::max(visibleHeight, minMainDim);
    const float extension = effectiveHeight - visibleHeight;
    geometry.y -= extension;
    geometry.height = effectiveHeight;
    geometry.x += crossDelta;
    geometry.width -= 2.0f * crossDelta;
    break;
  }
  case AttachedRevealDirection::Up: {
    const float originalHeight = geometry.height;
    const float visibleHeight = originalHeight * progress;
    const float effectiveHeight = std::max(visibleHeight, minMainDim);
    geometry.y += originalHeight - visibleHeight;
    geometry.height = effectiveHeight;
    geometry.x += crossDelta;
    geometry.width -= 2.0f * crossDelta;
    break;
  }
  case AttachedRevealDirection::Right: {
    const float visibleWidth = geometry.width * progress;
    const float effectiveWidth = std::max(visibleWidth, minMainDim);
    const float extension = effectiveWidth - visibleWidth;
    geometry.x -= extension;
    geometry.width = effectiveWidth;
    geometry.y += crossDelta;
    geometry.height -= 2.0f * crossDelta;
    break;
  }
  case AttachedRevealDirection::Left: {
    const float originalWidth = geometry.width;
    const float visibleWidth = originalWidth * progress;
    const float effectiveWidth = std::max(visibleWidth, minMainDim);
    geometry.x += originalWidth - visibleWidth;
    geometry.width = effectiveWidth;
    geometry.y += crossDelta;
    geometry.height -= 2.0f * crossDelta;
    break;
  }
  }

  m_attachedPanelGeometryCallback(m_output, geometry);
}

void PanelManager::applyPanelCompositorBlur() {
  // The blur region is submitted on every panel surface (attached subsurface or layer-shell),
  // but as of niri 26.04 the ext-background-effect-v1 implementation honors regions on
  // layer-shell / xdg-toplevel surfaces only — subsurfaces are ignored. Attached panels will
  // start blurring automatically once niri (or another compositor) gains subsurface support.
  if (m_surface == nullptr || m_activePanel == nullptr) {
    return;
  }
  if (m_config == nullptr || !m_config->config().shell.panel.backgroundBlur) {
    m_surface->clearBlurRegion();
    return;
  }

  int bx = m_panelInsetX;
  int by = m_panelInsetY;
  int bw = static_cast<int>(m_panelVisualWidth);
  int bh = static_cast<int>(m_panelVisualHeight);
  if (bw <= 0 || bh <= 0) {
    m_surface->clearBlurRegion();
    return;
  }

  if (!m_attachedToBar) {
    const float progress = std::clamp(m_detachedRevealProgress, 0.0f, 1.0f);
    const float s = 1.0f - 0.05f * (1.0f - progress);
    const int scaledW = static_cast<int>(std::lround(static_cast<float>(bw) * s));
    const int scaledH = static_cast<int>(std::lround(static_cast<float>(bh) * s));
    bx += (bw - scaledW) / 2;
    by += (bh - scaledH) / 2;
    bw = scaledW;
    bh = scaledH;
  } else {
    // Mirror the slide that the visible content node performs in applyAttachedReveal:
    // the full bg shape (body + concave bar-side bulges + convex away-side corners) is
    // tessellated at the bg's animated position, then strips are clipped to the surface
    // bounds below — the same clipping the m_attachedRevealClipNode applies to the
    // visible content. This keeps the blur region in lockstep with what's actually on
    // screen, so the bar-side concave bulges only contribute blur once the panel's
    // bar-side edge has slid into view (i.e. near the end of the open animation).
    const float progress = std::clamp(m_attachedRevealProgress, 0.0f, 1.0f);
    if (progress < 0.001f) {
      m_surface->clearBlurRegion();
      return;
    }
    const float panelW = static_cast<float>(m_panelVisualWidth);
    const float panelH = static_cast<float>(m_panelVisualHeight);
    switch (m_attachedRevealDirection) {
    case AttachedRevealDirection::Down:
      by -= static_cast<int>(std::lround(panelH * (1.0f - progress)));
      break;
    case AttachedRevealDirection::Up:
      by += static_cast<int>(std::lround(panelH * (1.0f - progress)));
      break;
    case AttachedRevealDirection::Right:
      bx -= static_cast<int>(std::lround(panelW * (1.0f - progress)));
      break;
    case AttachedRevealDirection::Left:
      bx += static_cast<int>(std::lround(panelW * (1.0f - progress)));
      break;
    }
  }

  const float radius = Style::radiusXl * m_activePanel->contentScale();
  const CornerShapes corners = m_attachedToBar ? attached_panel::cornerShapes(m_attachedBarPosition) : CornerShapes{};
  const RectInsets logicalInset =
      m_attachedToBar ? attached_panel::logicalInset(m_attachedBarPosition, radius) : RectInsets{};
  const Radii radii = Radii{radius, radius, radius, radius};
  auto strips = Surface::tessellateShape(bx, by, bw, bh, corners, logicalInset, radii);
  if (strips.empty()) {
    m_surface->clearBlurRegion();
    return;
  }

  if (m_attachedToBar && m_sceneRoot != nullptr) {
    const int clipMaxX = static_cast<int>(std::lround(m_sceneRoot->width()));
    const int clipMaxY = static_cast<int>(std::lround(m_sceneRoot->height()));
    std::vector<InputRect> clipped;
    clipped.reserve(strips.size());
    for (const auto& s : strips) {
      const int sxLeft = std::max(s.x, 0);
      const int sxRight = std::min(s.x + s.width, clipMaxX);
      const int syTop = std::max(s.y, 0);
      const int syBot = std::min(s.y + s.height, clipMaxY);
      if (sxRight > sxLeft && syBot > syTop) {
        clipped.push_back({sxLeft, syTop, sxRight - sxLeft, syBot - syTop});
      }
    }
    if (clipped.empty()) {
      m_surface->clearBlurRegion();
      return;
    }
    m_surface->setBlurRegion(clipped);
    return;
  }

  m_surface->setBlurRegion(strips);
}

void PanelManager::applyAttachedDecorationStyle() {
  if (!m_attachedToBar || m_activePanel == nullptr) {
    return;
  }
  const float scale = m_activePanel->contentScale();
  const float radius = Style::radiusXl * scale;

  if (m_bgNode != nullptr) {
    auto* bg = static_cast<Box*>(m_bgNode);
    bg->setFill(colorSpecFromRole(ColorRole::Surface, m_attachedBackgroundOpacity));
  }

  if (m_panelShadowNode != nullptr && m_config != nullptr) {
    const auto& shadowConfig = m_config->config().shell.shadow;
    const RoundedRectStyle shadowStyle =
        shell::surface_shadow::style(shadowConfig, m_attachedBackgroundOpacity,
                                     shell::surface_shadow::Shape{
                                         .corners = attached_panel::cornerShapes(m_attachedBarPosition),
                                         .logicalInset = attached_panel::logicalInset(m_attachedBarPosition, radius),
                                         .radius = Radii{radius, radius, radius, radius},
                                     });
    m_panelShadowNode->setStyle(shadowStyle);
  }

  if (m_panelContactShadowNode != nullptr) {
    const float contactAlpha = 0.16f * std::clamp(m_attachedBackgroundOpacity, 0.0f, 1.0f);
    const bool barIsBottom = m_attachedBarPosition == "bottom";
    const bool barIsRight = m_attachedBarPosition == "right";
    const bool barIsVertical = m_attachedBarPosition == "left" || m_attachedBarPosition == "right";
    // Gradient runs perpendicular to the bar edge, dark next to the bar, transparent toward
    // the panel interior. For top/left: dark at start. For bottom/right: dark at end.
    const bool darkAtStart = !(barIsBottom || barIsRight);
    const Color darkColor = rgba(0.0f, 0.0f, 0.0f, contactAlpha);
    const Color clearGradient = rgba(0.0f, 0.0f, 0.0f, 0.0f);
    const Color startColor = darkAtStart ? darkColor : clearGradient;
    const Color endColor = darkAtStart ? clearGradient : darkColor;
    const RoundedRectStyle contactStyle{
        .fill = startColor,
        .border = clearColor(),
        .fillMode = FillMode::LinearGradient,
        .gradientDirection = barIsVertical ? GradientDirection::Horizontal : GradientDirection::Vertical,
        .gradientStops = {GradientStop{0.0f, startColor}, GradientStop{0.0f, startColor}, GradientStop{1.0f, endColor},
                          GradientStop{1.0f, endColor}},
        .corners = attached_panel::cornerShapes(m_attachedBarPosition),
        .logicalInset = attached_panel::logicalInset(m_attachedBarPosition, radius),
        .radius = Radii{radius, radius, radius, radius},
        .softness = 1.0f,
        .borderWidth = 0.0f,
    };
    m_panelContactShadowNode->setStyle(contactStyle);
  }
}

void PanelManager::onConfigReloaded() {
  if (!isOpen() || m_config == nullptr || m_activePanel == nullptr) {
    return;
  }

  // Re-apply compositor blur for any open panel — covers both attached and layer-shell
  // panels reacting to shell.panel.background_blur changes.
  applyPanelCompositorBlur();

  // The remaining work is bar-config-driven and only applies to attached panels.
  if (!isAttachedOpen() || m_output == nullptr) {
    return;
  }
  // Panels that opt out of inheritance hold a fixed alpha; bar config reload doesn't affect them.
  if (!m_activePanel->inheritsBarBackgroundOpacity()) {
    return;
  }
  const float newOpacity = resolvePanelBarConfig(m_config, m_wayland, m_output, m_sourceBarName).backgroundOpacity;
  if (std::abs(newOpacity - m_attachedBackgroundOpacity) < 0.001f) {
    return;
  }
  m_attachedBackgroundOpacity = newOpacity;
  applyAttachedDecorationStyle();
  if (m_surface != nullptr) {
    m_surface->requestRedraw();
  }
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
      auto shadow = std::make_unique<Box>();
      m_panelShadowNode = static_cast<Box*>(sceneParent->addChild(std::move(shadow)));
      m_panelShadowNode->setZIndex(-1);
    }

    if (hasDecoration) {
      auto bg = std::make_unique<Box>();
      bg->setPanelStyle();
      if (m_attachedToBar) {
        const float radius = Style::radiusXl * m_activePanel->contentScale();
        bg->clearBorder();
        bg->setCornerShapes(attached_panel::cornerShapes(m_attachedBarPosition));
        bg->setLogicalInset(attached_panel::logicalInset(m_attachedBarPosition, radius));
        bg->setRadii(Radii{radius, radius, radius, radius});
        // Fill (opacity-dependent) is applied via applyAttachedDecorationStyle() below.
      }
      m_bgNode = sceneParent->addChild(std::move(bg));
    }

    if (hasDecoration && m_attachedToBar && m_attachedContactShadow) {
      auto contactShadow = std::make_unique<Box>();
      m_panelContactShadowNode = static_cast<Box*>(sceneParent->addChild(std::move(contactShadow)));
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
      applyDetachedReveal(0.0f);
      m_animations.animate(
          0.0f, 1.0f, Style::animNormal, Easing::EaseOutCubic, [this](float v) { applyDetachedReveal(v); }, {},
          m_sceneRoot.get());
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

  if (m_panelShadowNode != nullptr && m_config != nullptr) {
    const auto& shadowConfig = m_config->config().shell.shadow;
    const float shadowOffsetX = static_cast<float>(shadowConfig.offsetX);
    const float shadowOffsetY = static_cast<float>(shadowConfig.offsetY);
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
        std::min(std::max(kContactShadowBaseThickness * scale, attachedRadius * 2.0f), barIsVertical ? bgW : bgH);
    const bool barIsBottom = m_attachedBarPosition == "bottom";
    const bool barIsRight = m_attachedBarPosition == "right";
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
    m_panelContactShadowNode->setPosition(contactX, contactY);
    m_panelContactShadowNode->setSize(contactW, contactH);
  }

  // Re-apply opacity-dependent styling for bg/shadow/contact-shadow. Cheap and ensures
  // these stay in sync with m_attachedBackgroundOpacity if the bar config changed and
  // we got here via a buildScene path rather than onConfigReloaded().
  if (m_attachedToBar) {
    applyAttachedDecorationStyle();
  }

  const float kPadding = hasDecoration ? m_activePanel->contentScale() * Style::panelPadding : 0.0f;
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
  if (m_pointerInside) {
    m_inputDispatcher.syncPointerHover();
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
    if (m_pointerInside) {
      m_inputDispatcher.syncPointerHover();
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
          const std::string_view context = std::string_view(args).substr(sep + 1);
          wl_output* output =
              m_wayland != nullptr ? m_wayland->preferredPanelOutput(std::chrono::milliseconds(1200)) : nullptr;
          togglePanel(panelId, PanelOpenRequest{.output = output, .context = context});
        }
        return "ok\n";
      },
      "panel-toggle <id> [context]",
      "Toggle a panel by id, optionally with context (e.g. launcher /emo, control-center audio)");

  ipc.registerHandler(
      "settings-toggle",
      [this](const std::string&) -> std::string {
        openSettingsWindow();
        return "ok\n";
      },
      "settings-toggle", "Toggle the settings window");
}
