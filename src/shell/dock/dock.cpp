#include "core/ui_phase.h"
#include "shell/dock/dock.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "core/process.h"
#include "render/render_context.h"
#include "render/scene/input_area.h"
#include "render/scene/rect_node.h"
#include "ui/controls/label.h"
#include "system/desktop_entry.h"
#include "ui/controls/box.h"
#include "ui/controls/context_menu.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/image.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/layer_surface.h"
#include "wayland/popup_surface.h"
#include "wayland/wayland_connection.h"
#include "wayland/wayland_toplevels.h"

#include <algorithm>
#include <cctype>
#include <format>

#include <wayland-client-core.h>
#include "xdg-shell-client-protocol.h"

namespace {

constexpr Logger kLog("dock");

// Instance-count badge geometry — scales with icon size.
constexpr float kBadgeSizeRatio = 0.30f;  // fraction of icon size
constexpr float kBadgeMinSize   = 16.0f;  // minimum diameter in px
constexpr float kBadgeFontRatio = 0.72f;  // font size relative to badge diameter

// Thin strip (px) kept in the input region when auto-hide is in the hidden
// state, so the pointer can re-trigger show on approach to the screen edge.
constexpr std::int32_t kAutoHideTriggerPx = 2;

std::string toLower(std::string s) {
  for (auto& c : s) {
    c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  }
  return s;
}

std::string currentActiveAppIdLower(const WaylandConnection& wayland) {
  if (const auto active = wayland.activeToplevel(); active.has_value()) {
    return toLower(active->appId);
  }
  return {};
}

wl_output* currentDockFilterOutput(const WaylandConnection& wayland, const DockConfig& cfg) {
  if (!cfg.activeMonitorOnly) {
    return nullptr;
  }
  if (wl_output* output = wayland.activeToplevelOutput(); output != nullptr) {
    return output;
  }
  return wayland.preferredPanelOutput();
}

// Returns an anchor bitmask for the given position string.
std::uint32_t positionToAnchor(const std::string& pos) {
  if (pos == "top")    return LayerShellAnchor::Top;
  if (pos == "left")   return LayerShellAnchor::Left;
  if (pos == "right")  return LayerShellAnchor::Right;
  return LayerShellAnchor::Bottom; // default
}

// Shadow bleed helpers (identical to bar's logic).
struct ShadowBleed { std::int32_t left = 0, right = 0, up = 0, down = 0; };
ShadowBleed computeBleed(const DockConfig& cfg) {
  if (cfg.shadowBlur <= 0) return {};
  return {
      cfg.shadowBlur + std::max(0, -cfg.shadowOffsetX),
      cfg.shadowBlur + std::max(0, cfg.shadowOffsetX),
      cfg.shadowBlur + std::max(0, -cfg.shadowOffsetY),
      cfg.shadowBlur + std::max(0, cfg.shadowOffsetY),
  };
}

} // namespace

// ── Lifecycle ─────────────────────────────────────────────────────────────────

Dock::Dock() = default;

bool Dock::initialize(WaylandConnection& wayland, ConfigService* config, RenderContext* renderContext) {
  m_wayland      = &wayland;
  m_config       = config;
  m_renderContext = renderContext;

  const auto& cfg = m_config->config().dock;
  m_config->addReloadCallback([this]() {
    const auto& newCfg = m_config->config().dock;
    if (newCfg == m_lastDockConfig) {
      return;
    }
    reload();
  });

  m_lastDockConfig  = cfg;
  m_lastPinnedConfig = cfg.pinned;

  if (!cfg.enabled) {
    kLog.info("dock disabled in config");
    return true;
  }

  refreshPinnedAppsIfNeeded();
  syncInstances();
  return true;
}

void Dock::reload() {
  kLog.info("reloading config");
  const auto& cfg = m_config->config().dock;
  m_lastDockConfig   = cfg;
  m_lastPinnedConfig = cfg.pinned;

  if (!cfg.enabled) {
    closeAllInstances();
    return;
  }

  refreshPinnedAppsIfNeeded();

  m_instances.clear();
  m_surfaceMap.clear();
  m_hoveredInstance = nullptr;
  m_lastFilterOutput = nullptr;

  wl_display_roundtrip(m_wayland->display());
  syncInstances();
}

void Dock::show() {
  if (m_config == nullptr || !m_config->config().dock.enabled) {
    return;
  }

  refreshPinnedAppsIfNeeded();
  if (m_instances.empty()) {
    syncInstances();
    return;
  }

  refresh();
}

void Dock::closeAllInstances() {
  m_windowMenu.reset();
  m_itemMenu.reset();
  m_surfaceMap.clear();
  m_hoveredInstance = nullptr;
  m_lastFilterOutput = nullptr;
  m_instances.clear();
}

void Dock::onOutputChange() {
  if (!m_config->config().dock.enabled) {
    return;
  }
  syncInstances();
}

void Dock::refresh() {
  if (m_instances.empty()) {
    return;
  }

  refreshPinnedAppsIfNeeded();

  const auto& cfg = m_config->config().dock;
  const wl_output* filterOutput = currentDockFilterOutput(*m_wayland, cfg);
  const bool filterOutputChanged = (filterOutput != m_lastFilterOutput);
  m_lastFilterOutput = const_cast<wl_output*>(filterOutput);

  const std::string activeIdLower = currentActiveAppIdLower(*m_wayland);
  const auto runningIds  = cfg.showRunning ? m_wayland->runningAppIds(m_lastFilterOutput) : std::vector<std::string>{};
  std::vector<std::string> runningLower;
  runningLower.reserve(runningIds.size());
  for (const auto& id : runningIds) {
    runningLower.push_back(toLower(id));
  }

  for (auto& inst : m_instances) {
    if (inst->surface == nullptr || m_renderContext == nullptr) {
      continue;
    }

    inst->activeAppIdLower = activeIdLower;

    // Rebuild if model changed or running-only app set changed.
    bool needRebuild = (inst->modelSerial != m_modelSerial) || filterOutputChanged;

    if (!needRebuild && cfg.showRunning) {
      // Count running-only items expected vs current.
      const std::size_t expectedTotal = [&] {
        std::vector<DesktopEntry> entries = m_pinnedEntries;
        const auto& allEntries = desktopEntries();
        for (const auto& runId : runningIds) {
          const auto runLower = toLower(runId);
          bool present = false;
          for (const auto& e : entries) {
            if (toLower(e.id) == runLower || toLower(e.startupWmClass) == runLower || e.nameLower == runLower) {
              present = true;
              break;
            }
          }
          if (!present) {
            for (const auto& de : allEntries) {
              if (de.hidden || de.noDisplay) continue;
              if (toLower(de.startupWmClass) == runLower || de.nameLower == runLower || toLower(de.id) == runLower) {
                entries.push_back(de);
                break;
              }
            }
          }
        }
        return entries.size();
      }();
      if (expectedTotal != inst->items.size()) {
        needRebuild = true;
      }
    }

    // Sync running/active flags even without a rebuild (icon emphasis updates).
    for (auto& item : inst->items) {
      item.running = matchesRunningApp(item, runningLower);
      item.active  = matchesActiveApp(item, activeIdLower);
    }

    if (needRebuild) {
      rebuildItems(*inst);
    }

    m_renderContext->makeCurrent(inst->surface->renderTarget());
    m_renderContext->syncContentScale(inst->surface->renderTarget());
    updateVisuals(*inst);
    if (inst->sceneRoot != nullptr &&
        ((inst->sceneRoot->paintDirty() || inst->sceneRoot->layoutDirty()) || inst->animations.hasActive())) {
      if (inst->sceneRoot->layoutDirty()) {
        inst->surface->requestLayout();
      } else {
        inst->surface->requestRedraw();
      }
    }
  }
}

void Dock::toggleVisibility() {
  if (m_instances.empty()) {
    show();
  } else {
    closeAllInstances();
  }
}

void Dock::requestRedraw() {
  for (auto& inst : m_instances) {
    if (inst->surface != nullptr) {
      inst->surface->requestRedraw();
    }
  }
}

// ── Input ─────────────────────────────────────────────────────────────────────

bool Dock::onPointerEvent(const PointerEvent& event) {
  // Route to any open popup first (item menu takes priority over window picker).
  if (m_itemMenu != nullptr) {
    return routePopupEvent(m_itemMenu.get(), event);
  }
  if (m_windowMenu != nullptr) {
    return routePopupEvent(m_windowMenu.get(), event);
  }

  switch (event.type) {
  case PointerEvent::Type::Enter: {
    auto it = m_surfaceMap.find(event.surface);
    if (it == m_surfaceMap.end()) {
      break;
    }
    m_hoveredInstance = it->second;
    m_hoveredInstance->pointerInside = true;
    m_hoveredInstance->inputDispatcher.pointerEnter(static_cast<float>(event.sx),
                                                     static_cast<float>(event.sy), event.serial);
    // Auto-hide: show the dock when the pointer enters.
    if (m_config->config().dock.autoHide && m_hoveredInstance->sceneRoot != nullptr) {
      const float current = m_hoveredInstance->hideOpacity;
      m_hoveredInstance->animations.animate(
          current, 1.0f, Style::animNormal, Easing::EaseOutCubic,
          [inst = m_hoveredInstance](float v) {
            if (inst->sceneRoot) inst->sceneRoot->setOpacity(v);
            inst->hideOpacity = v;
          });
      // Restore full input region (full surface so shadow-margin edges don't
      // cause an immediate Leave when triggered from the edge of the strip).
      if (m_hoveredInstance->surface != nullptr) {
        const int sw = static_cast<int>(m_hoveredInstance->surface->width());
        const int sh = static_cast<int>(m_hoveredInstance->surface->height());
        m_hoveredInstance->surface->setInputRegion({InputRect{0, 0, sw, sh}});
      }
      m_hoveredInstance->surface->requestRedraw();
    }
    break;
  }
  case PointerEvent::Type::Leave: {
    if (m_hoveredInstance != nullptr) {
      m_hoveredInstance->pointerInside = false;
      m_hoveredInstance->inputDispatcher.pointerLeave();

      // Clear item hover state.
      for (auto& item : m_hoveredInstance->items) {
        if (item.hovered) {
          item.hovered = false;
          if (item.background != nullptr) {
            item.background->setFill(clearThemeColor());
          }
          if (m_hoveredInstance->sceneRoot) {
            m_hoveredInstance->sceneRoot->markPaintDirty();
          }
        }
      }

      // Auto-hide: start fade-out when pointer leaves, unless a popup is
      // being opened (m_popupOwnerInstance is set before the roundtrip inside
      // PopupSurface::initialize, which is where compositors like Hyprland
      // deliver the Leave event synchronously).
      if (m_config->config().dock.autoHide && m_popupOwnerInstance == nullptr) {
        startHideFadeOut(*m_hoveredInstance);
      }
      m_hoveredInstance = nullptr;
    }
    break;
  }
  case PointerEvent::Type::Motion: {
    if (m_hoveredInstance == nullptr) break;
    m_hoveredInstance->inputDispatcher.pointerMotion(static_cast<float>(event.sx),
                                                      static_cast<float>(event.sy), 0);
    break;
  }
  case PointerEvent::Type::Button: {
    if (m_hoveredInstance == nullptr) break;
    const bool pressed = (event.state == 1);
    m_hoveredInstance->inputDispatcher.pointerButton(static_cast<float>(event.sx),
                                                      static_cast<float>(event.sy),
                                                      event.button, pressed);
    break;
  }
  case PointerEvent::Type::Axis:
    break;
  }

  if (m_hoveredInstance != nullptr && m_hoveredInstance->sceneRoot != nullptr &&
      (m_hoveredInstance->sceneRoot->paintDirty() || m_hoveredInstance->sceneRoot->layoutDirty())) {
    if (m_hoveredInstance->sceneRoot->layoutDirty()) {
      m_hoveredInstance->surface->requestLayout();
    } else {
      m_hoveredInstance->surface->requestRedraw();
    }
  }

  return m_hoveredInstance != nullptr;
}

// ── Private: geometry helpers ─────────────────────────────────────────────────

bool Dock::isVertical() const {
  const auto& pos = m_config->config().dock.position;
  return pos == "left" || pos == "right";
}

std::int32_t Dock::dockThickness() const {
  const auto& cfg = m_config->config().dock;
  constexpr std::int32_t kCellPad = 6;
  return cfg.iconSize + kCellPad * 2 + cfg.padding * 2;
}

std::int32_t Dock::dockContentSize(std::size_t itemCount) const {
  const auto& cfg = m_config->config().dock;
  const auto n = static_cast<std::int32_t>(itemCount);
  constexpr std::int32_t kCellPad = 6;
  const std::int32_t cellSize = cfg.iconSize + kCellPad * 2;
  if (n == 0) return cellSize + cfg.padding * 2;
  return n * cellSize + std::max(0, n - 1) * cfg.itemSpacing + cfg.padding * 2;
}

// ── Private: instance management ─────────────────────────────────────────────

bool Dock::refreshPinnedAppsIfNeeded() {
  if (desktopEntriesVersion() == m_entriesVersion &&
      m_config->config().dock.pinned == m_lastPinnedConfig) {
    return false;
  }

  m_lastPinnedConfig = m_config->config().dock.pinned;
  m_entriesVersion   = desktopEntriesVersion();
  m_pinnedEntries.clear();

  const auto& entries = desktopEntries();

  for (const auto& pinnedId : m_config->config().dock.pinned) {
    const auto pinnedLower = toLower(pinnedId);
    bool found = false;

    for (const auto& entry : entries) {
      if (entry.hidden || entry.noDisplay) {
        continue;
      }
      // Match by entry ID (stem of the desktop file path, e.g. "firefox"),
      // by StartupWMClass (lower), or by Name (lower).
      const auto stemLower = toLower([&]{
        // Extract stem: "org.mozilla.firefox.desktop" → "firefox" (last component, no ext)
        const auto slash = entry.id.rfind('/');
        const auto base  = (slash == std::string::npos) ? entry.id : entry.id.substr(slash + 1);
        const auto dot   = base.rfind('.');
        return (dot == std::string::npos) ? base : base.substr(0, dot);
      }());

      if (stemLower == pinnedLower ||
          toLower(entry.startupWmClass) == pinnedLower ||
          entry.nameLower == pinnedLower ||
          entry.id == pinnedId) {
        m_pinnedEntries.push_back(entry);
        found = true;
        break;
      }
    }

    if (!found) {
      kLog.debug("pinned app not found: {}", pinnedId);
      // Add placeholder so the pinned slot is visible even when app is not installed.
      DesktopEntry placeholder;
      placeholder.id   = pinnedId;
      placeholder.name = pinnedId;
      placeholder.nameLower = pinnedLower;
      m_pinnedEntries.push_back(std::move(placeholder));
    }
  }

  ++m_modelSerial;
  kLog.debug("pinned app list: {} entries", m_pinnedEntries.size());
  return true;
}

void Dock::syncInstances() {
  const auto& outputs = m_wayland->outputs();

  // Remove instances for dead outputs.
  std::erase_if(m_instances, [&outputs](const auto& inst) {
    return !std::any_of(outputs.begin(), outputs.end(),
                        [&inst](const auto& o) { return o.name == inst->outputName; });
  });

  for (const auto& output : outputs) {
    if (!output.done) continue;
    const bool exists = std::any_of(m_instances.begin(), m_instances.end(),
                                    [&output](const auto& inst) { return inst->outputName == output.name; });
    if (!exists) {
      createInstance(output);
    }
  }
}

void Dock::createInstance(const WaylandOutput& output) {
  const auto& cfg = m_config->config().dock;
  kLog.info("creating dock on {} ({}) icon_size={} position={}",
            output.connectorName, output.description, cfg.iconSize, cfg.position);

  auto instance = std::make_unique<DockInstance>();
  instance->outputName = output.name;
  instance->output     = output.output;
  instance->scale      = output.scale;
  instance->activeAppIdLower = currentActiveAppIdLower(*m_wayland);

  const bool vert = isVertical();
  const auto sb   = computeBleed(cfg);
  const auto panelW = dockContentSize(cfg.pinned.size());
  const auto panelH = dockThickness();
  const auto anchor = positionToAnchor(cfg.position);
  const bool isBottom = (cfg.position == "bottom");
  const bool isRight  = (cfg.position == "right");

  // Surface dimensions incorporate shadow bleed + margin.
  std::uint32_t surfW, surfH;
  std::int32_t mL = 0, mR = 0, mT = 0, mB = 0;
  std::int32_t exclusiveZone = 0;

  if (!vert) {
    // Horizontal dock (top / bottom): centered, width = panel + shadow bleed sides + mH on each side.
    surfW = static_cast<std::uint32_t>(panelW + sb.left + sb.right);
    surfH = static_cast<std::uint32_t>(sb.up + panelH + std::min(cfg.marginV, sb.down));
    if (isBottom) {
      mB          = std::max(0, cfg.marginV - sb.down);
      surfH       = static_cast<std::uint32_t>(sb.up + panelH + std::min(cfg.marginV, sb.down));
      exclusiveZone = cfg.autoHide ? 0 : (panelH + std::min(cfg.marginV, sb.down));
    } else {
      mT          = std::max(0, cfg.marginV - sb.up);
      surfH       = static_cast<std::uint32_t>(std::min(cfg.marginV, sb.up) + panelH + sb.down);
      exclusiveZone = cfg.autoHide ? 0 : (std::min(cfg.marginV, sb.up) + panelH);
    }
    // marginH is applied symmetrically as compositor side margins.
    mL = cfg.marginH;
    mR = cfg.marginH;
  } else {
    // Vertical dock (left / right): centered vertically, height = panel + shadow bleed + mV.
    surfH = static_cast<std::uint32_t>(panelW + sb.up + sb.down);
    if (isRight) {
      mR          = std::max(0, cfg.marginH - sb.right);
      surfW       = static_cast<std::uint32_t>(sb.left + panelH + std::min(cfg.marginH, sb.right));
      exclusiveZone = cfg.autoHide ? 0 : (panelH + std::min(cfg.marginH, sb.right));
    } else {
      mL          = std::max(0, cfg.marginH - sb.left);
      surfW       = static_cast<std::uint32_t>(std::min(cfg.marginH, sb.left) + panelH + sb.right);
      exclusiveZone = cfg.autoHide ? 0 : (std::min(cfg.marginH, sb.left) + panelH);
    }
    mT = cfg.marginV;
    mB = cfg.marginV;
  }

  LayerSurfaceConfig lsCfg{
      .nameSpace     = "noctalia-dock",
      .layer         = LayerShellLayer::Top,
      .anchor        = anchor,
      .width         = surfW,
      .height        = surfH,
      .exclusiveZone = exclusiveZone,
      .marginTop     = mT,
      .marginRight   = mR,
      .marginBottom  = mB,
      .marginLeft    = mL,
      .defaultWidth  = surfW,
      .defaultHeight = surfH,
  };

  instance->surface = std::make_unique<LayerSurface>(*m_wayland, std::move(lsCfg));
  instance->surface->setRenderContext(m_renderContext);

  auto* inst = instance.get();
  instance->surface->setConfigureCallback(
      [inst](std::uint32_t /*w*/, std::uint32_t /*h*/) { inst->surface->requestLayout(); });
  instance->surface->setPrepareFrameCallback(
      [this, inst](bool needsUpdate, bool needsLayout) { prepareFrame(*inst, needsUpdate, needsLayout); });
  instance->surface->setAnimationManager(&instance->animations);

  if (!instance->surface->initialize(output.output)) {
    kLog.warn("failed to init dock surface for output {}", output.name);
    return;
  }

  m_surfaceMap[instance->surface->wlSurface()] = instance.get();
  m_instances.push_back(std::move(instance));
}

// ── Private: scene building ───────────────────────────────────────────────────

void Dock::prepareFrame(DockInstance& instance, bool /*needsUpdate*/, bool needsLayout) {
  if (m_renderContext == nullptr || instance.surface == nullptr) {
    return;
  }

  const auto width = instance.surface->width();
  const auto height = instance.surface->height();
  if (width == 0 || height == 0) {
    return;
  }

  m_renderContext->makeCurrent(instance.surface->renderTarget());

  const bool needsSceneBuild =
      instance.sceneRoot == nullptr || static_cast<std::uint32_t>(std::round(instance.sceneRoot->width())) != width ||
      static_cast<std::uint32_t>(std::round(instance.sceneRoot->height())) != height;
  if (needsSceneBuild || needsLayout) {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    buildScene(instance);
  }
}

void Dock::buildScene(DockInstance& instance) {
  uiAssertNotRendering("Dock::buildScene");
  if (m_renderContext == nullptr || instance.surface == nullptr) {
    return;
  }

  instance.activeAppIdLower = currentActiveAppIdLower(*m_wayland);

  const auto& cfg  = m_config->config().dock;
  const bool vert  = isVertical();

  const float w = static_cast<float>(instance.surface->width());
  const float h = static_cast<float>(instance.surface->height());

  const auto sb       = computeBleed(cfg);
  const float bleedL  = static_cast<float>(sb.left);
  const float bleedR  = static_cast<float>(sb.right);
  const float bleedU  = static_cast<float>(sb.up);
  const float bleedD  = static_cast<float>(sb.down);
  const float mV      = static_cast<float>(cfg.marginV);
  const float mH      = static_cast<float>(cfg.marginH);
  const bool isBottom = (cfg.position == "bottom");
  const bool isRight  = (cfg.position == "right");

  // Panel visual area within the surface.
  float panelX, panelY, panelW, panelH;
  if (!vert) {
    panelX = bleedL;
    panelY = isBottom ? bleedU : std::min(mV, bleedU);
    panelW = w - bleedL - bleedR;
    panelH = static_cast<float>(dockThickness());
  } else {
    panelX = isRight ? bleedL : std::min(mH, bleedL);
    panelY = bleedU;
    panelW = static_cast<float>(dockThickness());
    panelH = h - bleedU - bleedD;
  }

  const Radii radii{ static_cast<float>(cfg.radius), static_cast<float>(cfg.radius),
                     static_cast<float>(cfg.radius), static_cast<float>(cfg.radius) };

  if (instance.sceneRoot == nullptr) {
    instance.sceneRoot = std::make_unique<Node>();
    instance.sceneRoot->setAnimationManager(&instance.animations);
    instance.sceneRoot->setSize(w, h);

    // Shadow
    if (cfg.shadowBlur > 0) {
      auto shadow = std::make_unique<RectNode>();
      instance.shadow = static_cast<RectNode*>(instance.sceneRoot->addChild(std::move(shadow)));
    }

    // Panel background
    auto panel = std::make_unique<Box>();
    panel->setRadius(static_cast<float>(cfg.radius));
    instance.panel = static_cast<Box*>(instance.sceneRoot->addChild(std::move(panel)));

    // Item row
    auto row = std::make_unique<Flex>();
    row->setDirection(vert ? FlexDirection::Vertical : FlexDirection::Horizontal);
    row->setGap(static_cast<float>(cfg.itemSpacing));
    row->setAlign(FlexAlign::Center);
    row->setPadding(static_cast<float>(cfg.padding));
    instance.row = static_cast<Flex*>(instance.panel->addChild(std::move(row)));

    // Wire up InputDispatcher.
    instance.inputDispatcher.setSceneRoot(instance.sceneRoot.get());
    instance.inputDispatcher.setCursorShapeCallback(
        [this](std::uint32_t serial, std::uint32_t shape) { m_wayland->setCursorShape(serial, shape); });

    // Populate items and wire up palette reactivity.
    rebuildItems(instance);

    if (cfg.autoHide) {
      // Start hidden immediately — no intro animation.
      instance.sceneRoot->setOpacity(0.0f);
      instance.hideOpacity = 0.0f;
    } else {
      // Normal intro fade-in.
      instance.sceneRoot->setOpacity(0.0f);
      instance.animations.animate(0.0f, 1.0f, Style::animSlow, Easing::EaseOutCubic,
                                  [root = instance.sceneRoot.get()](float v) { root->setOpacity(v); },
                                  [inst = &instance]() { inst->hideOpacity = 1.0f; }, instance.sceneRoot.get());
    }

    instance.surface->setSceneRoot(instance.sceneRoot.get());
  }

  // Update root size on reconfigure.
  instance.sceneRoot->setSize(w, h);

  // Shadow
  if (instance.shadow != nullptr) {
    const float sSize = static_cast<float>(cfg.shadowBlur);
    const RoundedRectStyle shadowStyle{
        .fill      = rgba(0.0f, 0.0f, 0.0f, 0.5f),
        .fillEnd   = {},
        .border    = clearColor(),
        .fillMode  = FillMode::Solid,
        .radius    = radii,
        .softness  = sSize,
    };
    instance.shadow->setStyle(shadowStyle);
    instance.shadow->setZIndex(-1);
    instance.shadow->setPosition(panelX + static_cast<float>(cfg.shadowOffsetX),
                                 panelY + static_cast<float>(cfg.shadowOffsetY));
    instance.shadow->setSize(panelW, panelH);
  }

  // Panel
  applyPanelPalette(instance);
  instance.panel->setPosition(panelX, panelY);
  instance.panel->setSize(panelW, panelH);

  // Row fills panel (padding already applied via Flex::setPadding).
  instance.row->setPosition(0.0f, 0.0f);
  instance.row->setSize(panelW, panelH);
  instance.row->layout(*m_renderContext);

  // Input region: trigger strip when hidden (autoHide), full panel otherwise.
  if (cfg.autoHide && instance.hideOpacity < 0.5f) {
    const int surfW = static_cast<int>(w);
    const int surfH = static_cast<int>(h);
    if (!vert) {
      instance.surface->setInputRegion({InputRect{0, surfH - kAutoHideTriggerPx, surfW, kAutoHideTriggerPx}});
    } else if (cfg.position == "left") {
      instance.surface->setInputRegion({InputRect{surfW - kAutoHideTriggerPx, 0, kAutoHideTriggerPx, surfH}});
    } else {
      instance.surface->setInputRegion({InputRect{0, 0, kAutoHideTriggerPx, surfH}});
    }
  } else {
    instance.surface->setInputRegion({InputRect{
        static_cast<int>(panelX),
        static_cast<int>(panelY),
        static_cast<int>(panelW),
        static_cast<int>(panelH),
    }});
  }

  // Palette reactivity.
  instance.paletteConn = paletteChanged().connect([inst = &instance, this] {
    applyPanelPalette(*inst);
    if (inst->surface) inst->surface->requestRedraw();
  });

  updateVisuals(instance);
}

void Dock::applyPanelPalette(DockInstance& instance) {
  if (instance.panel == nullptr) return;
  const float opacity = m_config->config().dock.backgroundOpacity;
  instance.panel->setFill(roleColor(ColorRole::Surface, opacity));
  instance.panel->setBorder(roleColor(ColorRole::Outline), 0.0f);
}

// ── Private: item population ──────────────────────────────────────────────────

void Dock::rebuildItems(DockInstance& instance) {
  uiAssertNotRendering("Dock::rebuildItems");
  if (instance.row == nullptr || m_renderContext == nullptr) {
    return;
  }

  const auto& cfg   = m_config->config().dock;
  const bool vert   = isVertical();
  const float iSize = static_cast<float>(cfg.iconSize);

  for (auto& item : instance.items) {
    if (item.scaleAnimId != 0) {
      instance.animations.cancel(item.scaleAnimId);
      item.scaleAnimId = 0;
    }
    if (item.opacityAnimId != 0) {
      instance.animations.cancel(item.opacityAnimId);
      item.opacityAnimId = 0;
    }
  }

  // Clear previous items by recreating the row.
  if (instance.row != nullptr && instance.panel != nullptr) {
    instance.panel->removeChild(instance.row);
    instance.row = nullptr;
  }
  instance.items.clear();

  // Create a fresh row.
  auto freshRow = std::make_unique<Flex>();
  freshRow->setDirection(vert ? FlexDirection::Vertical : FlexDirection::Horizontal);
  freshRow->setGap(static_cast<float>(cfg.itemSpacing));
  freshRow->setAlign(FlexAlign::Center);
  freshRow->setPadding(static_cast<float>(cfg.padding));
  instance.row = static_cast<Flex*>(instance.panel != nullptr
      ? instance.panel->addChild(std::move(freshRow))
      : instance.sceneRoot->addChild(std::move(freshRow)));

  // Determine items: pinned + (optionally) running-only apps not in pinned.
  std::vector<DesktopEntry> itemEntries = m_pinnedEntries;
  wl_output* filterOutput = currentDockFilterOutput(*m_wayland, cfg);

  if (cfg.showRunning) {
    const auto runningIds = m_wayland->runningAppIds(filterOutput);
    const auto& allEntries = desktopEntries();

    for (const auto& runId : runningIds) {
      const auto runLower = toLower(runId);

      // Skip if already in itemEntries (covers pinned entries).
      bool alreadyPresent = false;
      for (const auto& itm : itemEntries) {
        if (toLower(itm.id) == runLower ||
            toLower(itm.startupWmClass) == runLower ||
            itm.nameLower == runLower) {
          alreadyPresent = true;
          break;
        }
      }
      if (alreadyPresent) continue;

      // Find desktop entry.
      for (const auto& de : allEntries) {
        if (de.hidden || de.noDisplay) continue;
        if (toLower(de.startupWmClass) == runLower ||
            de.nameLower == runLower ||
            toLower(de.id) == runLower) {
          itemEntries.push_back(de);
          break;
        }
      }
    }
  }

  const auto activeIdLower = instance.activeAppIdLower;
  const auto runningIds    = m_wayland->runningAppIds(filterOutput);
  std::vector<std::string> runningLower;
  for (const auto& id : runningIds) runningLower.push_back(toLower(id));

  // Reserve up-front so emplace_back never reallocates while lambdas hold raw pointers.
  instance.items.reserve(itemEntries.size());

  for (const auto& entry : itemEntries) {
    auto& item = instance.items.emplace_back();
    item.entry               = entry;
    item.idLower             = toLower(entry.id);
    item.startupWmClassLower = toLower(entry.startupWmClass);
    item.active              = matchesActiveApp(item, activeIdLower);
    item.running             = matchesRunningApp(item, runningLower);

    // Cell is icon + kCellPad on each side; hover bg fills the full cell.
    constexpr float kCellPad = 6.0f; // px extra on each side
    const float cellMain  = iSize + 2.0f * kCellPad;
    const float cellCross = iSize + 2.0f * kCellPad;
    auto areaNode = std::make_unique<InputArea>();
    if (!vert) {
      areaNode->setSize(cellMain, cellCross);
    } else {
      areaNode->setSize(cellCross, cellMain);
    }

    // Hover background — fills cell, radius matches dock panel.
    auto bg = std::make_unique<Box>();
    bg->setSize(cellMain, cellMain); // square — excludes indicator strip
    bg->setPosition(0.0f, 0.0f);
    bg->setRadius(static_cast<float>(cfg.radius));
    bg->setFill(clearThemeColor());
    item.background = static_cast<Box*>(areaNode->addChild(std::move(bg)));

    // Icon centred inside the padded cell.
    const std::string& iconPath = m_iconResolver.resolve(entry.icon);
    auto iconImg = std::make_unique<Image>();
    if (!iconPath.empty() && m_renderContext != nullptr) {
      iconImg->setSourceFile(*m_renderContext, iconPath, cfg.iconSize, true);
    }
    iconImg->setSize(iSize, iSize);
    iconImg->setPosition(kCellPad, kCellPad);

    if (iconImg->hasImage()) {
      item.iconImage = static_cast<Image*>(areaNode->addChild(std::move(iconImg)));
    } else {
      // Fallback: app glyph.
      auto glyph = std::make_unique<Glyph>();
      glyph->setGlyph("apps");
      glyph->setGlyphSize(iSize * 0.8f);
      glyph->setColor(roleColor(ColorRole::OnSurface));
      glyph->setSize(iSize, iSize);
      glyph->setPosition(kCellPad, kCellPad);
      item.iconGlyph = static_cast<Glyph*>(areaNode->addChild(std::move(glyph)));
    }

    // Instance-count badge — top-right corner of the icon, initially hidden.
    if (cfg.showInstanceCount) {
      const float bd = std::max(kBadgeMinSize, iSize * kBadgeSizeRatio);
      const float badgeX = kCellPad + iSize - bd * 0.55f;
      const float badgeY = kCellPad - bd * 0.45f;

      auto badgeBox = std::make_unique<Box>();
      badgeBox->setRadius(bd * 0.5f);
      badgeBox->setSize(bd, bd);
      badgeBox->setPosition(badgeX, badgeY);
      badgeBox->setVisible(false);
      item.badge = static_cast<Box*>(areaNode->addChild(std::move(badgeBox)));

      auto labelNode = std::make_unique<Label>();
      labelNode->setFontSize(bd * kBadgeFontRatio);
      labelNode->setBold(true);
      labelNode->setMaxLines(1);
      labelNode->setVisible(false);
      item.badgeLabel = static_cast<Label*>(item.badge->addChild(std::move(labelNode)));
    }

    // Pointer callbacks.
    auto* itemPtr  = &item;
    auto* instPtr  = &instance;

    areaNode->setOnEnter([itemPtr, instPtr, this](const InputArea::PointerData&) {
      if (!itemPtr->hovered) {
        itemPtr->hovered = true;
        if (itemPtr->background) {
          itemPtr->background->setFill(roleColor(ColorRole::Hover, 0.8f));
        }
        if (instPtr->sceneRoot) instPtr->sceneRoot->markPaintDirty();
      }
    });
    areaNode->setOnLeave([itemPtr, instPtr]() {
      if (itemPtr->hovered) {
        itemPtr->hovered = false;
        if (itemPtr->background) {
          itemPtr->background->setFill(clearThemeColor());
        }
        if (instPtr->sceneRoot) instPtr->sceneRoot->markPaintDirty();
      }
    });
    areaNode->setAcceptedButtons(BTN_LEFT | BTN_RIGHT);
    areaNode->setOnClick([itemPtr, instPtr, this](const InputArea::PointerData& d) {
      if (d.button == BTN_LEFT) {
        handleItemClick(*instPtr, *itemPtr);
      } else if (d.button == BTN_RIGHT) {
        openItemMenu(*instPtr, *itemPtr);
      }
    });

    item.area = static_cast<InputArea*>(instance.row->addChild(std::move(areaNode)));
  }

  instance.modelSerial = m_modelSerial;

  // Force surface resize when item count changes.
  resizeSurface(instance);
}

void Dock::resizeSurface(DockInstance& instance) {
  if (instance.surface == nullptr) {
    return;
  }

  const auto& cfg = m_config->config().dock;
  const bool vert = isVertical();
  const auto sb   = computeBleed(cfg);
  const auto panelW = dockContentSize(instance.items.size());
  const auto panelH = dockThickness();
  const bool isBottom = (cfg.position == "bottom");

  std::uint32_t surfW, surfH;
  if (!vert) {
    surfW = static_cast<std::uint32_t>(panelW + sb.left + sb.right);
    surfH = isBottom
        ? static_cast<std::uint32_t>(sb.up + panelH + std::min(cfg.marginV, sb.down))
        : static_cast<std::uint32_t>(std::min(cfg.marginV, sb.up) + panelH + sb.down);
  } else {
    const bool isRight = (cfg.position == "right");
    surfW = isRight
        ? static_cast<std::uint32_t>(sb.left + panelH + std::min(cfg.marginH, sb.right))
        : static_cast<std::uint32_t>(std::min(cfg.marginH, sb.left) + panelH + sb.right);
    surfH = static_cast<std::uint32_t>(panelW + sb.up + sb.down);
  }

  if (instance.surface->width() != surfW || instance.surface->height() != surfH) {
    instance.surface->requestSize(surfW, surfH);
  }
}

// ── Private: visual update ────────────────────────────────────────────────────

void Dock::updateVisuals(DockInstance& instance) {
  const auto& cfg = m_config->config().dock;

  for (auto& item : instance.items) {
    const float iconScale = item.active ? cfg.activeScale : cfg.inactiveScale;
    const float iconOpacity = item.active ? cfg.activeOpacity : cfg.inactiveOpacity;
    Node* iconNode = item.iconImage != nullptr
        ? static_cast<Node*>(item.iconImage)
        : static_cast<Node*>(item.iconGlyph);

    if (iconNode != nullptr) {
      if (item.visualScale < 0.0f) {
        item.visualScale = iconScale;
        iconNode->setScale(iconScale);
      } else if (std::abs(item.visualScale - iconScale) > 0.001f) {
        if (item.scaleAnimId != 0) {
          instance.animations.cancel(item.scaleAnimId);
        }
        item.scaleAnimId = instance.animations.animate(
            item.visualScale, iconScale, Style::animNormal, Easing::EaseOutCubic,
            [node = iconNode, itemPtr = &item](float value) {
              itemPtr->visualScale = value;
              node->setScale(value);
            },
            [itemPtr = &item] {
              itemPtr->scaleAnimId = 0;
            });
      }

      if (item.visualOpacity < 0.0f) {
        item.visualOpacity = iconOpacity;
        iconNode->setOpacity(iconOpacity);
      } else if (std::abs(item.visualOpacity - iconOpacity) > 0.001f) {
        if (item.opacityAnimId != 0) {
          instance.animations.cancel(item.opacityAnimId);
        }
        item.opacityAnimId = instance.animations.animate(
            item.visualOpacity, iconOpacity, Style::animNormal, Easing::EaseOutCubic,
            [node = iconNode, itemPtr = &item](float value) {
              itemPtr->visualOpacity = value;
              node->setOpacity(value);
            },
            [itemPtr = &item] {
              itemPtr->opacityAnimId = 0;
            });
      }
    }

    // Instance-count badge.
    if (item.badge != nullptr && item.badgeLabel != nullptr) {
      const auto windows = m_wayland->windowsForApp(item.idLower, item.startupWmClassLower,
                        currentDockFilterOutput(*m_wayland, cfg));
      const std::size_t count = windows.size();
      if (count != item.instanceCount) {
        item.instanceCount = count;
        const bool show = (count >= 2);
        item.badge->setVisible(show);
        item.badgeLabel->setVisible(show);
        if (show) {
          const std::string label = (count > 9) ? "9+" : std::to_string(count);
          item.badgeLabel->setText(label);
          item.badgeLabel->setColor(roleColor(ColorRole::OnError));
          item.badge->setFill(roleColor(ColorRole::Error));
          if (m_renderContext != nullptr) {
            const float bd = std::max(kBadgeMinSize,
                static_cast<float>(cfg.iconSize) * kBadgeSizeRatio);
            item.badgeLabel->measure(*m_renderContext);
            item.badgeLabel->setPosition(
                std::round((bd - item.badgeLabel->width()) * 0.5f),
                std::round((bd - item.badgeLabel->height()) * 0.5f));
          }
        }
      }
    }
  }
}

// ── Private: helpers ──────────────────────────────────────────────────────────

bool Dock::matchesActiveApp(const DockItemView& item, std::string_view activeIdLower) const {
  if (activeIdLower.empty()) return false;
  return item.idLower == activeIdLower ||
         item.startupWmClassLower == activeIdLower ||
         item.entry.nameLower == activeIdLower;
}

bool Dock::matchesRunningApp(const DockItemView& item, const std::vector<std::string>& runningLower) const {
  for (const auto& rid : runningLower) {
    if (item.idLower == rid || item.startupWmClassLower == rid || item.entry.nameLower == rid) {
      return true;
    }
  }
  return false;
}

void Dock::launchEntry(const DesktopEntry& entry) {
  if (entry.exec.empty()) {
    kLog.warn("no exec for {}", entry.name);
    return;
  }
  // Strip desktop-entry field codes (%u, %f, %F, %U, …).
  std::string cmd;
  cmd.reserve(entry.exec.size());
  for (std::size_t i = 0; i < entry.exec.size(); ++i) {
    if (entry.exec[i] == '%' && i + 1 < entry.exec.size()) {
      ++i; // skip field code char
      continue;
    }
    cmd += entry.exec[i];
  }
  while (!cmd.empty() && std::isspace(static_cast<unsigned char>(cmd.back()))) {
    cmd.pop_back();
  }
  kLog.info("launching: {}", cmd);
  (void)process::launchShellCommand(cmd);
}

// ── Private: click handling ───────────────────────────────────────────────────

void Dock::handleItemClick(DockInstance& instance, DockItemView& item) {
  // Find all windows matching this item's app.
  auto windows = m_wayland->windowsForApp(item.idLower, item.startupWmClassLower,
                                          currentDockFilterOutput(*m_wayland, m_config->config().dock));

  if (windows.empty()) {
    // Nothing running — launch the app.
    launchEntry(item.entry);
    return;
  }

  if (windows.size() == 1) {
    // Exactly one window: activate it directly.
    m_wayland->activateToplevel(windows[0].handle);
    return;
  }

  // Multiple windows: show a picker popup.
  openWindowPicker(instance, item, std::move(windows));
}

// ── Private: window picker popup ─────────────────────────────────────────────

static constexpr float kMenuWidth = 240.0f;

void Dock::openWindowPicker(DockInstance& instance, DockItemView& item,
                             std::vector<ToplevelInfo> windows) {
  if (!m_wayland->hasXdgShell()) {
    // Fallback: activate the first window if we can't show a popup.
    if (!windows.empty()) {
      m_wayland->activateToplevel(windows[0].handle);
    }
    return;
  }

  closeWindowPicker();

  m_popupOwnerInstance = &instance;
  auto menu = std::make_unique<DockPopup>();

  // Build context menu entries (window titles).
  std::vector<ContextMenuControlEntry> entries;
  entries.reserve(windows.size());
  for (std::int32_t i = 0; i < static_cast<std::int32_t>(windows.size()); ++i) {
    const auto& title = windows[i].title.empty() ? item.entry.name : windows[i].title;
    entries.push_back(ContextMenuControlEntry{
        .id       = i,
        .label    = title,
        .enabled  = true,
        .separator = false,
        .hasSubmenu = false,
    });
    menu->handles.push_back(windows[i].handle);
  }

  // Compute popup height.
  const float menuHeight = ContextMenuControl::preferredHeight(entries, entries.size());

  // Determine anchor / gravity + gap based on dock position.
  const auto& cfg = m_config->config().dock;
  const bool isBottom = (cfg.position == "bottom");
  const bool isTop    = (cfg.position == "top");
  const bool isRight  = (cfg.position == "right");

  std::uint32_t anchor  = XDG_POSITIONER_ANCHOR_NONE;
  std::uint32_t gravity = XDG_POSITIONER_GRAVITY_NONE;
  std::int32_t offsetX  = 0;
  std::int32_t offsetY  = 0;
  const std::int32_t kGapBottom = std::max(2, static_cast<std::int32_t>(Style::spaceLg));
  const std::int32_t kGap       = std::max(2, static_cast<std::int32_t>(Style::spaceMd));

  if (isBottom) {
    anchor  = XDG_POSITIONER_ANCHOR_TOP;
    gravity = XDG_POSITIONER_GRAVITY_TOP;
    offsetY = -kGapBottom;
  } else if (isTop) {
    anchor  = XDG_POSITIONER_ANCHOR_BOTTOM;
    gravity = XDG_POSITIONER_GRAVITY_BOTTOM;
    offsetY = kGap;
  } else if (isRight) {
    anchor  = XDG_POSITIONER_ANCHOR_LEFT;
    gravity = XDG_POSITIONER_GRAVITY_LEFT;
    offsetX = -kGap;
  } else { // left
    anchor  = XDG_POSITIONER_ANCHOR_RIGHT;
    gravity = XDG_POSITIONER_GRAVITY_RIGHT;
    offsetX = kGap;
  }

  const auto sb = computeBleed(cfg);
  const std::int32_t panelThk = dockThickness();
  const std::int32_t ptrX = static_cast<std::int32_t>(m_wayland->lastPointerX());
  const std::int32_t ptrY = static_cast<std::int32_t>(m_wayland->lastPointerY());
  const std::int32_t halfCell = cfg.iconSize / 2;

  // Anchor rect: pointer-centred on main axis × panel face on cross axis.
  std::int32_t aX, aY, aW, aH;
  if (isBottom) {
    // Panel top face is at sb.up.
    aX = ptrX - halfCell; aY = sb.up;
    aW = halfCell * 2;    aH = panelThk;
  } else if (isTop) {
    const std::int32_t panelFace = std::min(cfg.marginV, sb.up) + panelThk;
    aX = ptrX - halfCell; aY = 0;
    aW = halfCell * 2;    aH = panelFace;
  } else if (isRight) {
    aX = sb.left;         aY = ptrY - halfCell;
    aW = panelThk;        aH = halfCell * 2;
  } else { // left
    const std::int32_t panelFace = std::min(cfg.marginH, sb.left) + panelThk;
    aX = 0;               aY = ptrY - halfCell;
    aW = panelFace;       aH = halfCell * 2;
  }

  PopupSurfaceConfig popupCfg{
      .anchorX             = aX,
      .anchorY             = aY,
      .anchorWidth         = std::max(1, aW),
      .anchorHeight        = std::max(1, aH),
      .width               = static_cast<std::uint32_t>(kMenuWidth),
      .height              = static_cast<std::uint32_t>(std::max(1.0f, menuHeight)),
      .anchor              = anchor,
      .gravity             = gravity,
      .constraintAdjustment = XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_X |
                              XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_Y |
                              XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_X  |
                              XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_Y,
      .offsetX             = offsetX,
      .offsetY             = offsetY,
      .serial              = m_wayland->lastInputSerial(),
      .grab                = true,
  };

  menu->surface = std::make_unique<PopupSurface>(*m_wayland);
  menu->surface->setRenderContext(m_renderContext);

  auto* menuPtr = menu.get();

  menu->surface->setConfigureCallback(
      [menuPtr](std::uint32_t /*w*/, std::uint32_t /*h*/) { menuPtr->surface->requestLayout(); });
  menu->surface->setPrepareFrameCallback(
      [this, menuPtr, entries](bool /*needsUpdate*/, bool needsLayout) {
        if (m_renderContext == nullptr || menuPtr->surface == nullptr) {
          return;
        }

        const auto width = menuPtr->surface->width();
        const auto height = menuPtr->surface->height();
        if (width == 0 || height == 0) {
          return;
        }

        m_renderContext->makeCurrent(menuPtr->surface->renderTarget());

        const bool needsSceneBuild =
            menuPtr->sceneRoot == nullptr ||
            static_cast<std::uint32_t>(std::round(menuPtr->sceneRoot->width())) != width ||
            static_cast<std::uint32_t>(std::round(menuPtr->sceneRoot->height())) != height;
        if (!needsSceneBuild && !needsLayout) {
          return;
        }

        UiPhaseScope layoutPhase(UiPhase::Layout);

        const auto fw = static_cast<float>(width);
        const auto fh = static_cast<float>(height);

        menuPtr->sceneRoot = std::make_unique<Node>();
        menuPtr->sceneRoot->setSize(fw, fh);

        auto ctrl = std::make_unique<ContextMenuControl>();
        ctrl->setMenuWidth(fw);
        ctrl->setMaxVisible(entries.size());
        ctrl->setEntries(entries);
        ctrl->setRedrawCallback([menuPtr]() {
          if (menuPtr->surface) menuPtr->surface->requestRedraw();
        });
        ctrl->setOnActivate([this, menuPtr](const ContextMenuControlEntry& e) {
          const auto idx = static_cast<std::size_t>(e.id);
          auto* handle = (idx < menuPtr->handles.size()) ? menuPtr->handles[idx] : nullptr;
          DeferredCall::callLater([this, handle]() {
            if (handle != nullptr) {
              m_wayland->activateToplevel(handle);
            }
            closeWindowPicker();
          });
        });
        ctrl->setPosition(0.0f, 0.0f);
        ctrl->setSize(fw, fh);
        ctrl->layout(*m_renderContext);

        menuPtr->sceneRoot->addChild(std::move(ctrl));
        menuPtr->inputDispatcher.setSceneRoot(menuPtr->sceneRoot.get());
        menuPtr->inputDispatcher.setCursorShapeCallback(
            [this](std::uint32_t serial, std::uint32_t shape) { m_wayland->setCursorShape(serial, shape); });
        menuPtr->surface->setSceneRoot(menuPtr->sceneRoot.get());
      });

  menu->surface->setDismissedCallback([this]() { closeWindowPicker(); });

  auto* layerSurface = m_wayland->layerSurfaceFor(instance.surface->wlSurface());
  if (layerSurface == nullptr ||
      !menu->surface->initialize(layerSurface, instance.output, popupCfg)) {
    kLog.warn("dock: failed to create window-picker popup");
    return;
  }

  menu->wlSurface = menu->surface->wlSurface();
  m_windowMenu = std::move(menu);
}

void Dock::closeWindowPicker() {
  DockInstance* owner = m_popupOwnerInstance;
  m_popupOwnerInstance = nullptr;
  m_windowMenu.reset();
  if (m_config->config().dock.autoHide && owner != nullptr && owner->hideOpacity > 0.0f) {
    owner->pointerInside = false;
    if (m_hoveredInstance == owner) {
      m_hoveredInstance = nullptr;
    }
    startHideFadeOut(*owner);
  }
}

// ── Private: generic popup routing ───────────────────────────────────────────

bool Dock::routePopupEvent(DockPopup* popup, const PointerEvent& event) {
  const bool onPopup = (event.surface != nullptr && event.surface == popup->wlSurface);

  switch (event.type) {
  case PointerEvent::Type::Enter:
    if (onPopup) {
      popup->pointerInside = true;
      popup->inputDispatcher.pointerEnter(static_cast<float>(event.sx),
                                          static_cast<float>(event.sy), event.serial);
    }
    break;
  case PointerEvent::Type::Leave:
    if (onPopup) {
      popup->pointerInside = false;
      popup->inputDispatcher.pointerLeave();
    }
    break;
  case PointerEvent::Type::Motion:
    if (onPopup || popup->pointerInside) {
      popup->inputDispatcher.pointerMotion(static_cast<float>(event.sx),
                                           static_cast<float>(event.sy), 0);
    }
    break;
  case PointerEvent::Type::Button:
    if (onPopup || popup->pointerInside) {
      const bool pressed = (event.state == 1);
      popup->inputDispatcher.pointerButton(static_cast<float>(event.sx),
                                           static_cast<float>(event.sy),
                                           event.button, pressed);
    }
    break;
  case PointerEvent::Type::Axis:
    break;
  }

  if (popup->surface != nullptr && popup->sceneRoot != nullptr &&
      (popup->sceneRoot->paintDirty() || popup->sceneRoot->layoutDirty())) {
    if (popup->sceneRoot->layoutDirty()) {
      popup->surface->requestLayout();
    } else {
      popup->surface->requestRedraw();
    }
  }

  // Always consume: popup holds the grab.
  return true;
}

// ── Private: item context menu (right-click) ──────────────────────────────────

void Dock::startHideFadeOut(DockInstance& inst) {
  const float current = inst.hideOpacity;
  inst.animations.animate(
      current, 0.0f, Style::animSlow, Easing::EaseInQuad,
      [&inst](float v) {
        if (inst.sceneRoot) inst.sceneRoot->setOpacity(v);
        inst.hideOpacity = v;
      },
      [&inst, this]() {
        if (inst.surface == nullptr) return;
        const auto& cfg = m_config->config().dock;
        const bool vert = isVertical();
        const auto sb   = computeBleed(cfg);
        const auto panelW = dockContentSize(inst.items.size());
        const auto panelH = dockThickness();
        const auto surfW = static_cast<int>(
            vert ? (sb.left + panelH + sb.right) : (panelW + sb.left + sb.right));
        const auto surfH = static_cast<int>(
            vert ? (panelW + sb.up + sb.down)   : (sb.up + panelH + cfg.marginV));
        if (!vert) {
          inst.surface->setInputRegion({InputRect{0, surfH - kAutoHideTriggerPx, surfW, kAutoHideTriggerPx}});
        } else if (cfg.position == "left") {
          inst.surface->setInputRegion({InputRect{surfW - kAutoHideTriggerPx, 0, kAutoHideTriggerPx, surfH}});
        } else {
          inst.surface->setInputRegion({InputRect{0, 0, kAutoHideTriggerPx, surfH}});
        }
      });
  if (inst.surface) inst.surface->requestRedraw();
}

void Dock::closeItemMenu() {
  DockInstance* owner = m_popupOwnerInstance;
  m_popupOwnerInstance = nullptr;
  m_itemMenu.reset();
  // Fade the owner out — the pointer left the dock to interact with the menu,
  // whether or not the compositor sent a Leave event at that time.
  if (m_config->config().dock.autoHide && owner != nullptr && owner->hideOpacity > 0.0f) {
    owner->pointerInside = false;
    if (m_hoveredInstance == owner) {
      m_hoveredInstance = nullptr;
    }
    startHideFadeOut(*owner);
  }
}

void Dock::launchAction(const DesktopAction& action) {
  if (action.exec.empty()) {
    kLog.warn("no exec for action {}", action.name);
    return;
  }
  // Strip desktop-entry field codes (%u, %f, %F, %U, …).
  std::string cmd;
  cmd.reserve(action.exec.size());
  for (std::size_t i = 0; i < action.exec.size(); ++i) {
    if (action.exec[i] == '%' && i + 1 < action.exec.size()) {
      ++i;
      continue;
    }
    cmd += action.exec[i];
  }
  while (!cmd.empty() && std::isspace(static_cast<unsigned char>(cmd.back()))) {
    cmd.pop_back();
  }
  kLog.info("launching action: {}", cmd);
  (void)process::launchShellCommand(cmd);
}

void Dock::openItemMenu(DockInstance& instance, DockItemView& item) {
  if (!m_wayland->hasXdgShell()) return;

  // Close existing popups before opening the new one.
  closeWindowPicker();
  closeItemMenu();

  m_popupOwnerInstance = &instance;
  auto menu = std::make_unique<DockPopup>();

  // Collect running windows for "Close" / "Close All" entries.
  auto windows = m_wayland->windowsForApp(item.idLower, item.startupWmClassLower,
                                          currentDockFilterOutput(*m_wayland, m_config->config().dock));
  for (const auto& w : windows) {
    menu->handles.push_back(w.handle);
  }

  // IDs 0..N-1 → desktop actions; -1 → Close; -2 → Close All.
  std::vector<ContextMenuControlEntry> entries;
  entries.reserve(item.entry.actions.size() + 3);

  for (std::int32_t i = 0; i < static_cast<std::int32_t>(item.entry.actions.size()); ++i) {
    entries.push_back(ContextMenuControlEntry{
        .id         = i,
        .label      = item.entry.actions[static_cast<std::size_t>(i)].name,
        .enabled    = true,
        .separator  = false,
        .hasSubmenu = false,
    });
  }

  const std::size_t runCount = menu->handles.size();
  if (runCount > 0) {
    if (!entries.empty()) {
    // Separator between app actions and window-management entries.
      entries.push_back(ContextMenuControlEntry{
          .id = -3, .label = {}, .enabled = false, .separator = true, .hasSubmenu = false});
    }
    if (runCount == 1) {
      entries.push_back(ContextMenuControlEntry{
          .id = -1, .label = "Close", .enabled = true, .separator = false, .hasSubmenu = false});
    } else {
      entries.push_back(ContextMenuControlEntry{
          .id = -2, .label = "Close All", .enabled = true, .separator = false, .hasSubmenu = false});
    }
  }

  if (entries.empty()) return; // nothing to show

  // Compute popup height.
  const float menuHeight = ContextMenuControl::preferredHeight(entries, entries.size());

  // Determine anchor / gravity + gap based on dock position.
  const auto& cfg = m_config->config().dock;
  const bool isBottom = (cfg.position == "bottom");
  const bool isTop    = (cfg.position == "top");
  const bool isRight  = (cfg.position == "right");

  std::uint32_t anchor  = XDG_POSITIONER_ANCHOR_NONE;
  std::uint32_t gravity = XDG_POSITIONER_GRAVITY_NONE;
  std::int32_t offsetX  = 0;
  std::int32_t offsetY  = 0;
  const std::int32_t kGapBottom = std::max(2, static_cast<std::int32_t>(Style::spaceLg));
  const std::int32_t kGap       = std::max(2, static_cast<std::int32_t>(Style::spaceMd));

  if (isBottom) {
    anchor  = XDG_POSITIONER_ANCHOR_TOP;
    gravity = XDG_POSITIONER_GRAVITY_TOP;
    offsetY = -kGapBottom;
  } else if (isTop) {
    anchor  = XDG_POSITIONER_ANCHOR_BOTTOM;
    gravity = XDG_POSITIONER_GRAVITY_BOTTOM;
    offsetY = kGap;
  } else if (isRight) {
    anchor  = XDG_POSITIONER_ANCHOR_LEFT;
    gravity = XDG_POSITIONER_GRAVITY_LEFT;
    offsetX = -kGap;
  } else { // left
    anchor  = XDG_POSITIONER_ANCHOR_RIGHT;
    gravity = XDG_POSITIONER_GRAVITY_RIGHT;
    offsetX = kGap;
  }

  const auto sb = computeBleed(cfg);
  const std::int32_t panelThk = dockThickness();
  const std::int32_t ptrX = static_cast<std::int32_t>(m_wayland->lastPointerX());
  const std::int32_t ptrY = static_cast<std::int32_t>(m_wayland->lastPointerY());
  const std::int32_t halfCell = cfg.iconSize / 2;

  // Anchor rect: pointer-centred on main axis × panel face on cross axis.
  std::int32_t aX, aY, aW, aH;
  if (isBottom) {
    // Panel top face is at sb.up.
    aX = ptrX - halfCell; aY = sb.up;
    aW = halfCell * 2;    aH = panelThk;
  } else if (isTop) {
    const std::int32_t panelFace = std::min(cfg.marginV, sb.up) + panelThk;
    aX = ptrX - halfCell; aY = 0;
    aW = halfCell * 2;    aH = panelFace;
  } else if (isRight) {
    aX = sb.left;         aY = ptrY - halfCell;
    aW = panelThk;        aH = halfCell * 2;
  } else { // left
    const std::int32_t panelFace = std::min(cfg.marginH, sb.left) + panelThk;
    aX = 0;               aY = ptrY - halfCell;
    aW = panelFace;       aH = halfCell * 2;
  }

  PopupSurfaceConfig popupCfg{
      .anchorX              = aX,
      .anchorY              = aY,
      .anchorWidth          = std::max(1, aW),
      .anchorHeight         = std::max(1, aH),
      .width                = static_cast<std::uint32_t>(kMenuWidth),
      .height               = static_cast<std::uint32_t>(std::max(1.0f, menuHeight)),
      .anchor               = anchor,
      .gravity              = gravity,
      .constraintAdjustment = XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_X |
                              XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_Y |
                              XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_X  |
                              XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_Y,
      .offsetX              = offsetX,
      .offsetY              = offsetY,
      .serial               = m_wayland->lastInputSerial(),
      .grab                 = true,
  };

  menu->surface = std::make_unique<PopupSurface>(*m_wayland);
  menu->surface->setRenderContext(m_renderContext);

  auto* menuPtr = menu.get();

  // Capture actions by value — item may be rebuilt before the callback fires.
  auto entryActions = item.entry.actions;

  menu->surface->setConfigureCallback(
      [menuPtr](std::uint32_t /*w*/, std::uint32_t /*h*/) { menuPtr->surface->requestLayout(); });
  menu->surface->setPrepareFrameCallback(
      [this, menuPtr, entries, entryActions](bool /*needsUpdate*/, bool needsLayout) {
        if (m_renderContext == nullptr || menuPtr->surface == nullptr) {
          return;
        }

        const auto width = menuPtr->surface->width();
        const auto height = menuPtr->surface->height();
        if (width == 0 || height == 0) {
          return;
        }

        m_renderContext->makeCurrent(menuPtr->surface->renderTarget());

        const bool needsSceneBuild =
            menuPtr->sceneRoot == nullptr ||
            static_cast<std::uint32_t>(std::round(menuPtr->sceneRoot->width())) != width ||
            static_cast<std::uint32_t>(std::round(menuPtr->sceneRoot->height())) != height;
        if (!needsSceneBuild && !needsLayout) {
          return;
        }

        UiPhaseScope layoutPhase(UiPhase::Layout);

        const auto fw = static_cast<float>(width);
        const auto fh = static_cast<float>(height);

        menuPtr->sceneRoot = std::make_unique<Node>();
        menuPtr->sceneRoot->setSize(fw, fh);

        auto ctrl = std::make_unique<ContextMenuControl>();
        ctrl->setMenuWidth(fw);
        ctrl->setMaxVisible(entries.size());
        ctrl->setEntries(entries);
        ctrl->setRedrawCallback([menuPtr]() {
          if (menuPtr->surface) menuPtr->surface->requestRedraw();
        });
        ctrl->setOnActivate([this, menuPtr, entryActions](const ContextMenuControlEntry& e) {
          const std::int32_t id = e.id;
          auto closingHandles = menuPtr->handles;
          DeferredCall::callLater([this, id, entryActions, closingHandles = std::move(closingHandles)]() mutable {
            if (id >= 0) {
              const auto idx = static_cast<std::size_t>(id);
              if (idx < entryActions.size()) {
                launchAction(entryActions[idx]);
              }
            } else if (id == -1 && !closingHandles.empty()) {
              m_wayland->closeToplevel(closingHandles[0]);
            } else if (id == -2) {
              for (auto* handle : closingHandles) {
                m_wayland->closeToplevel(handle);
              }
            }
            closeItemMenu();
          });
        });
        ctrl->setPosition(0.0f, 0.0f);
        ctrl->setSize(fw, fh);
        ctrl->layout(*m_renderContext);

        menuPtr->sceneRoot->addChild(std::move(ctrl));
        menuPtr->inputDispatcher.setSceneRoot(menuPtr->sceneRoot.get());
        menuPtr->inputDispatcher.setCursorShapeCallback(
            [this](std::uint32_t serial, std::uint32_t shape) { m_wayland->setCursorShape(serial, shape); });
        menuPtr->surface->setSceneRoot(menuPtr->sceneRoot.get());
      });

  menu->surface->setDismissedCallback([this]() { closeItemMenu(); });

  auto* layerSurface = m_wayland->layerSurfaceFor(instance.surface->wlSurface());
  if (layerSurface == nullptr ||
      !menu->surface->initialize(layerSurface, instance.output, popupCfg)) {
    kLog.warn("dock: failed to create item-menu popup");
    return;
  }

  menu->wlSurface = menu->surface->wlSurface();
  m_itemMenu = std::move(menu);
}
