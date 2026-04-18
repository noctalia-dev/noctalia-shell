#include "shell/tray/tray_menu.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "core/ui_phase.h"
#include "dbus/tray/tray_service.h"
#include "render/render_context.h"
#include "ui/controls/context_menu.h"
#include "ui/style.h"
#include "wayland/layer_surface.h"
#include "wayland/wayland_connection.h"
#include "wayland/wayland_seat.h"
#include "xdg-shell-client-protocol.h"

#include <algorithm>
#include <optional>
#include <string>

namespace {

  constexpr Logger kLog("tray");

  constexpr float kMenuWidth = 246.0f;

  constexpr float kSurfaceWidth = kMenuWidth;

  constexpr std::uint32_t kPopupConstraintAdjust =
      XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_X | XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_Y |
      XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_X | XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_Y;

  bool containsTrayWidget(const std::vector<std::string>& widgets) {
    return std::find(widgets.begin(), widgets.end(), "tray") != widgets.end();
  }

  std::size_t visibleEntryLimit(std::size_t entryCount) { return std::max<std::size_t>(1, entryCount); }

  std::optional<BarConfig> resolveTrayBarConfig(ConfigService* config, WaylandConnection* wayland, wl_output* output) {
    if (config == nullptr) {
      return std::nullopt;
    }

    const WaylandOutput* wlOutput = nullptr;
    if (wayland != nullptr && output != nullptr) {
      wlOutput = wayland->findOutputByWl(output);
    }

    std::optional<BarConfig> fallback;
    for (const auto& base : config->config().bars) {
      BarConfig resolved = base;
      if (wlOutput != nullptr) {
        resolved = ConfigService::resolveForOutput(base, *wlOutput);
      }
      if (!resolved.enabled) {
        continue;
      }
      if (!fallback.has_value()) {
        fallback = resolved;
      }
      if (containsTrayWidget(resolved.startWidgets) || containsTrayWidget(resolved.centerWidgets) ||
          containsTrayWidget(resolved.endWidgets)) {
        return resolved;
      }
    }
    return fallback;
  }

  struct PopupPlacement {
    std::int32_t anchorX = 0;
    std::int32_t anchorY = 0;
    std::int32_t anchorWidth = 1;
    std::int32_t anchorHeight = 1;
    std::uint32_t anchor = XDG_POSITIONER_ANCHOR_NONE;
    std::uint32_t gravity = XDG_POSITIONER_GRAVITY_TOP;
    std::int32_t offsetX = 0;
    std::int32_t offsetY = 2;
    ContextSubmenuDirection submenuDirection = ContextSubmenuDirection::Right;
  };

  PopupPlacement popupPlacementForBar(const BarConfig& bar, std::int32_t anchorX, std::int32_t anchorY) {
    const std::int32_t kGap = std::max(2, static_cast<std::int32_t>(Style::spaceMd));
    const std::int32_t iconSize = std::clamp(bar.thickness - 10, 16, 40);
    const std::int32_t halfIcon = iconSize / 2;
    PopupPlacement placement{
        .anchorX = anchorX - halfIcon,
        .anchorY = anchorY - halfIcon,
        .anchorWidth = iconSize,
        .anchorHeight = iconSize,
    };

    if (bar.position == "bottom") {
      placement.anchor = XDG_POSITIONER_ANCHOR_TOP;
      placement.gravity = XDG_POSITIONER_GRAVITY_TOP;
      placement.offsetX = 0;
      placement.offsetY = -kGap;
      placement.submenuDirection = ContextSubmenuDirection::Right;
      return placement;
    }

    if (bar.position == "left") {
      placement.anchor = XDG_POSITIONER_ANCHOR_RIGHT;
      placement.gravity = XDG_POSITIONER_GRAVITY_RIGHT;
      placement.offsetX = kGap;
      placement.offsetY = 0;
      placement.submenuDirection = ContextSubmenuDirection::Right;
      return placement;
    }

    if (bar.position == "right") {
      placement.anchor = XDG_POSITIONER_ANCHOR_LEFT;
      placement.gravity = XDG_POSITIONER_GRAVITY_LEFT;
      placement.offsetX = -kGap;
      placement.offsetY = 0;
      placement.submenuDirection = ContextSubmenuDirection::Left;
      return placement;
    }

    placement.anchor = XDG_POSITIONER_ANCHOR_BOTTOM;
    placement.gravity = XDG_POSITIONER_GRAVITY_BOTTOM;
    placement.offsetX = 0;
    placement.offsetY = kGap;
    placement.submenuDirection = ContextSubmenuDirection::Right;
    return placement;
  }

} // namespace

void TrayMenu::initialize(WaylandConnection& wayland, ConfigService* config, TrayService* tray,
                          RenderContext* renderContext) {
  m_wayland = &wayland;
  m_config = config;
  m_tray = tray;
  m_renderContext = renderContext;
}

void TrayMenu::onTrayChanged() {
  if (!m_visible) {
    return;
  }
  refreshEntries();
  if (m_entries.empty()) {
    close();
    return;
  }
  rebuildScenes();
}

void TrayMenu::toggleForItem(const std::string& itemId) {
  if (itemId.empty()) {
    close();
    return;
  }

  if (m_visible && itemId == m_activeItemId) {
    close();
    return;
  }

  // popup_done fires on press; setOnClick fires on release. By the time we get here
  // the menu is already closed (m_visible = false) even though the user is closing it.
  // Suppress reopening if the same item was dismissed within the last 300 ms.
  if (!m_visible && itemId == m_lastClosedItemId) {
    const auto elapsed = std::chrono::steady_clock::now() - m_lastCloseTime;
    if (elapsed < std::chrono::milliseconds(300)) {
      m_lastClosedItemId.clear();
      return;
    }
  }

  m_activeItemId = itemId;
  refreshEntries();

  m_visible = true;
  ensureSurface();
  if (m_instance == nullptr || m_instance->surface == nullptr) {
    close();
    return;
  }

  // Notify the dbusmenu server the root menu is being opened. Well-behaved
  // servers (including Electron) rely on paired opened/closed events to reset
  // internal state — skipping them causes their handlers to desync after many
  // open/close cycles, eventually returning errors on every GetLayout.
  if (m_tray != nullptr) {
    m_tray->notifyMenuOpened(m_activeItemId);
  }

  rebuildScenes();
}

void TrayMenu::close() {
  if (!m_visible) {
    return;
  }
  m_lastClosedItemId = m_activeItemId;
  m_lastCloseTime = std::chrono::steady_clock::now();
  m_visible = false;
  // Stop any in-flight retry: continuing to hit GetLayout while the user is
  // spam-clicking the tray is what wedges Electron's dbusmenu handler.
  m_retryTimer.stop();
  closeSubmenu();
  // Send the "closed" event before tearing down the surface so the server
  // has a chance to reset its internal open-state before the next open.
  if (m_tray != nullptr && !m_activeItemId.empty()) {
    m_tray->notifyMenuClosed(m_activeItemId);
  }
  destroySurface();
}

void TrayMenu::onThemeChanged() {
  if (!m_visible) {
    return;
  }
  rebuildScenes();
}

void TrayMenu::requestLayout() {
  if (!m_visible) {
    return;
  }
  if (m_instance != nullptr && m_instance->surface != nullptr) {
    m_instance->surface->requestLayout();
  }
  if (m_submenuInstance != nullptr && m_submenuInstance->surface != nullptr) {
    m_submenuInstance->surface->requestLayout();
  }
}

bool TrayMenu::onPointerEvent(const PointerEvent& event) {
  if (!m_visible || m_instance == nullptr) {
    return false;
  }

  // Route to submenu first — it holds the active grab when open.
  if (m_submenuInstance != nullptr) {
    auto* sub = m_submenuInstance.get();
    const bool onSub = (event.surface != nullptr && event.surface == sub->wlSurface);
    bool subConsumed = false;

    switch (event.type) {
    case PointerEvent::Type::Enter:
      if (onSub) {
        sub->pointerInside = true;
        sub->inputDispatcher.pointerEnter(static_cast<float>(event.sx), static_cast<float>(event.sy), event.serial);
      }
      break;
    case PointerEvent::Type::Leave:
      if (onSub) {
        sub->pointerInside = false;
        sub->inputDispatcher.pointerLeave();
      }
      break;
    case PointerEvent::Type::Motion:
      if (onSub || sub->pointerInside) {
        if (onSub)
          sub->pointerInside = true;
        sub->inputDispatcher.pointerMotion(static_cast<float>(event.sx), static_cast<float>(event.sy), 0);
        subConsumed = true;
      }
      break;
    case PointerEvent::Type::Button:
      if (onSub || sub->pointerInside) {
        if (onSub)
          sub->pointerInside = true;
        const bool pressed = (event.state == 1);
        sub->inputDispatcher.pointerButton(static_cast<float>(event.sx), static_cast<float>(event.sy), event.button,
                                           pressed);
        subConsumed = true;
        if (m_submenuInstance == nullptr) {
          return subConsumed;
        }
      }
      break;
    case PointerEvent::Type::Axis:
      break;
    }

    if (sub->surface != nullptr && sub->sceneRoot != nullptr &&
        (sub->sceneRoot->paintDirty() || sub->sceneRoot->layoutDirty())) {
      if (sub->sceneRoot->layoutDirty()) {
        sub->surface->requestLayout();
      } else {
        sub->surface->requestRedraw();
      }
    }

    if (subConsumed) {
      return subConsumed;
    }
  }

  auto* inst = m_instance.get();
  const bool onThisSurface = (event.surface != nullptr && event.surface == inst->wlSurface);
  bool consumed = false;

  switch (event.type) {
  case PointerEvent::Type::Enter:
    if (onThisSurface) {
      inst->pointerInside = true;
      inst->inputDispatcher.pointerEnter(static_cast<float>(event.sx), static_cast<float>(event.sy), event.serial);
    }
    break;
  case PointerEvent::Type::Leave:
    if (onThisSurface) {
      inst->pointerInside = false;
      inst->inputDispatcher.pointerLeave();
    }
    break;
  case PointerEvent::Type::Motion:
    if (onThisSurface || inst->pointerInside) {
      if (onThisSurface) {
        inst->pointerInside = true;
      }
      inst->inputDispatcher.pointerMotion(static_cast<float>(event.sx), static_cast<float>(event.sy), 0);
      consumed = true;
    }
    break;
  case PointerEvent::Type::Button:
    if (onThisSurface || inst->pointerInside) {
      if (onThisSurface) {
        inst->pointerInside = true;
      }
      const bool pressed = (event.state == 1);
      inst->inputDispatcher.pointerButton(static_cast<float>(event.sx), static_cast<float>(event.sy), event.button,
                                          pressed);
      consumed = true;
      if (!m_visible || m_instance == nullptr) {
        return consumed;
      }
    }
    break;
  case PointerEvent::Type::Axis:
    break;
  }

  if (inst->surface != nullptr && inst->sceneRoot != nullptr &&
      (inst->sceneRoot->paintDirty() || inst->sceneRoot->layoutDirty())) {
    if (inst->sceneRoot->layoutDirty()) {
      inst->surface->requestLayout();
    } else {
      inst->surface->requestRedraw();
    }
  }

  if (event.type == PointerEvent::Type::Button && event.state == 1 && !consumed) {
    close();
  }
  return consumed;
}

void TrayMenu::onFontChanged() {
  if (m_instance != nullptr && m_instance->surface != nullptr) {
    m_instance->surface->requestLayout();
  }
  if (m_submenuInstance != nullptr && m_submenuInstance->surface != nullptr) {
    m_submenuInstance->surface->requestLayout();
  }
}

void TrayMenu::refreshEntries() {
  m_retryTimer.stop();
  m_entries.clear();
  if (m_tray == nullptr || m_activeItemId.empty()) {
    return;
  }
  m_entries = m_tray->menuEntries(m_activeItemId);
  if (m_entries.empty()) {
    m_entries.push_back(TrayMenuEntry{
        .id = -1,
        .label = "No menu items...",
        .enabled = false,
        .visible = true,
        .separator = false,
        .hasSubmenu = false,
    });
    // Short retry window for apps that need a moment to populate after registration.
    // LayoutUpdated from TrayService will also trigger a refresh via onTrayChanged,
    // so this is just a fallback for servers that don't emit it reliably.
    scheduleEntryRetry(0);
  }
}

void TrayMenu::scheduleEntryRetry(int attempt) {
  // Delays: 300ms, 900ms, 2000ms — total window ~3s. Kept small on purpose:
  // longer retry loops hammer the server while the user is clicking and that is
  // what wedges Electron's dbusmenu handler.
  constexpr int kDelays[] = {300, 900, 2000};
  constexpr int kMaxAttempts = static_cast<int>(sizeof(kDelays) / sizeof(kDelays[0]));
  if (attempt >= kMaxAttempts || m_tray == nullptr) {
    return;
  }
  const auto delay = std::chrono::milliseconds(kDelays[attempt]);
  const std::string capturedItemId = m_activeItemId;
  m_retryTimer.start(delay, [this, attempt, capturedItemId]() {
    // Abort if the menu closed or the user switched tray items — we only retry
    // while the placeholder menu is still visible to the user.
    if (!m_visible || m_tray == nullptr || m_activeItemId != capturedItemId) {
      return;
    }
    auto fresh = m_tray->menuEntries(capturedItemId);
    if (fresh.empty()) {
      scheduleEntryRetry(attempt + 1);
      return;
    }
    kLog.info("tray menu recovered (attempt {}) for id={}", attempt + 1, capturedItemId);
    m_entries = std::move(fresh);
    rebuildScenes();
  });
}

uint32_t TrayMenu::submenuHeightPx() const {
  std::vector<ContextMenuControlEntry> entries;
  entries.reserve(m_submenuEntries.size());
  for (const auto& entry : m_submenuEntries) {
    entries.push_back(ContextMenuControlEntry{
        .id = entry.id,
        .label = entry.label,
        .enabled = entry.enabled,
        .separator = entry.separator,
        .hasSubmenu = entry.hasSubmenu,
    });
  }
  return static_cast<uint32_t>(ContextMenuControl::preferredHeight(entries, visibleEntryLimit(entries.size())));
}

uint32_t TrayMenu::surfaceHeightPx() const {
  std::vector<ContextMenuControlEntry> entries;
  entries.reserve(m_entries.size());
  for (const auto& entry : m_entries) {
    entries.push_back(ContextMenuControlEntry{
        .id = entry.id,
        .label = entry.label,
        .enabled = entry.enabled,
        .separator = entry.separator,
        .hasSubmenu = entry.hasSubmenu,
    });
  }
  return static_cast<uint32_t>(ContextMenuControl::preferredHeight(entries, visibleEntryLimit(entries.size())));
}

bool TrayMenu::ownsSurface(wl_surface* surface) const {
  return m_instance != nullptr && surface != nullptr && m_instance->wlSurface == surface;
}

void TrayMenu::ensureSurface() {
  if (m_instance != nullptr) {
    return;
  }
  if (m_wayland == nullptr || m_renderContext == nullptr) {
    return;
  }

  wl_surface* parentWlSurface = m_wayland->lastPointerSurface();
  auto* parentLayerSurface = m_wayland->layerSurfaceFor(parentWlSurface);
  wl_output* output = m_wayland->lastPointerOutput();
  const std::uint32_t serial = m_wayland->lastInputSerial();

  if (parentLayerSurface == nullptr || output == nullptr || serial == 0) {
    kLog.warn("tray menu: missing popup anchor context (parent={}, output={}, serial={})",
              parentLayerSurface != nullptr, output != nullptr, serial);
    return;
  }

  int anchorX = 0;
  int anchorY = 0;
  if (m_wayland->hasPointerPosition()) {
    anchorX = static_cast<int>(m_wayland->lastPointerX());
    anchorY = static_cast<int>(m_wayland->lastPointerY());
  }

  auto inst = std::make_unique<MenuInstance>();
  inst->output = output;
  inst->surface = std::make_unique<PopupSurface>(*m_wayland);
  auto* instPtr = inst.get();

  inst->surface->setConfigureCallback(
      [instPtr](uint32_t /*width*/, uint32_t /*height*/) { instPtr->surface->requestLayout(); });
  inst->surface->setPrepareFrameCallback([this, instPtr](bool needsUpdate, bool needsLayout) {
    prepareMainMenuFrame(*instPtr, needsUpdate, needsLayout);
  });
  inst->surface->setDismissedCallback([this]() { close(); });
  inst->surface->setRenderContext(m_renderContext);

  const auto surfaceWidth = static_cast<uint32_t>(kSurfaceWidth);
  const auto surfaceHeight = surfaceHeightPx();
  PopupPlacement placement{};
  if (const auto bar = resolveTrayBarConfig(m_config, m_wayland, output); bar.has_value()) {
    placement = popupPlacementForBar(*bar, anchorX, anchorY);
    anchorX = placement.anchorX;
    anchorY = placement.anchorY;
  }
  inst->submenuDirection = placement.submenuDirection;
  auto popupConfig = PopupSurfaceConfig{
      .anchorX = anchorX,
      .anchorY = anchorY,
      .anchorWidth = placement.anchorWidth,
      .anchorHeight = placement.anchorHeight,
      .width = surfaceWidth,
      .height = surfaceHeight,
      .anchor = placement.anchor,
      .gravity = placement.gravity,
      .constraintAdjustment = kPopupConstraintAdjust,
      .offsetX = placement.offsetX,
      .offsetY = placement.offsetY,
      .serial = serial,
      .grab = true,
  };

  if (!inst->surface->initialize(parentLayerSurface, output, popupConfig)) {
    kLog.warn("tray menu: failed to create popup surface");
    return;
  }

  inst->wlSurface = inst->surface->wlSurface();
  m_instance = std::move(inst);
}

void TrayMenu::destroySurface() {
  if (m_instance != nullptr) {
    m_instance->inputDispatcher.setSceneRoot(nullptr);
  }
  m_instance.reset();
}

void TrayMenu::rebuildScenes() {
  uiAssertNotRendering("TrayMenu::rebuildScenes");
  if (!m_visible) {
    return;
  }
  if (!m_entries.empty() && m_instance != nullptr && m_instance->surface != nullptr) {
    m_instance->surface->requestLayout();
  }
  if (!m_submenuEntries.empty() && m_submenuInstance != nullptr && m_submenuInstance->surface != nullptr) {
    m_submenuInstance->surface->requestLayout();
  }
}

void TrayMenu::prepareMainMenuFrame(MenuInstance& inst, bool /*needsUpdate*/, bool needsLayout) {
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
                               static_cast<uint32_t>(std::round(inst.sceneRoot->width())) != width ||
                               static_cast<uint32_t>(std::round(inst.sceneRoot->height())) != height;
  if (needsSceneBuild || needsLayout) {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    buildScene(inst, width, height);
  }
}

void TrayMenu::buildScene(MenuInstance& inst, uint32_t width, uint32_t height) {
  uiAssertNotRendering("TrayMenu::buildScene");
  const auto w = static_cast<float>(width);
  const auto h = static_cast<float>(height);

  inst.sceneRoot = std::make_unique<Node>();
  inst.sceneRoot->setSize(w, h);

  std::vector<ContextMenuControlEntry> entries;
  entries.reserve(m_entries.size());
  for (const auto& entry : m_entries) {
    entries.push_back(ContextMenuControlEntry{
        .id = entry.id,
        .label = entry.label,
        .enabled = entry.enabled,
        .separator = entry.separator,
        .hasSubmenu = entry.hasSubmenu,
    });
  }

  auto menu = std::make_unique<ContextMenuControl>();
  menu->setMenuWidth(w);
  menu->setMaxVisible(visibleEntryLimit(m_entries.size()));
  menu->setSubmenuDirection(inst.submenuDirection);
  menu->setEntries(std::move(entries));
  menu->setRedrawCallback([&inst]() {
    if (inst.surface != nullptr) {
      inst.surface->requestRedraw();
    }
  });
  menu->setOnActivate([this](const ContextMenuControlEntry& entry) {
    if (m_tray == nullptr || m_activeItemId.empty()) {
      return;
    }
    DeferredCall::callLater([this, entry]() {
      if (m_tray != nullptr) {
        (void)m_tray->activateMenuEntry(m_activeItemId, entry.id);
      }
      close();
    });
  });
  menu->setOnSubmenuOpen(
      [this](const ContextMenuControlEntry& entry, float rowCenterY) { openSubmenu(entry.id, rowCenterY); });
  menu->setPosition(0.0f, 0.0f);
  menu->setSize(w, h);
  menu->layout(*m_renderContext);
  inst.sceneRoot->addChild(std::move(menu));

  inst.inputDispatcher.setSceneRoot(inst.sceneRoot.get());
  inst.inputDispatcher.setCursorShapeCallback(
      [this](uint32_t serial, uint32_t shape) { m_wayland->setCursorShape(serial, shape); });
  inst.surface->setSceneRoot(inst.sceneRoot.get());
}

void TrayMenu::closeSubmenu() {
  if (m_submenuInstance != nullptr) {
    m_submenuInstance->inputDispatcher.setSceneRoot(nullptr);
  }
  // Notify the server before clearing state so the parent id is still valid.
  if (m_tray != nullptr && !m_activeItemId.empty() && m_submenuParentEntryId != 0) {
    m_tray->notifyMenuClosed(m_activeItemId, m_submenuParentEntryId);
  }
  m_submenuInstance.reset();
  m_submenuEntries.clear();
  m_submenuParentEntryId = 0;
}

void TrayMenu::openSubmenu(std::int32_t parentEntryId, float rowCenterY) {
  closeSubmenu();

  if (m_instance == nullptr || m_instance->surface == nullptr || m_tray == nullptr) {
    return;
  }

  m_submenuEntries = m_tray->menuEntriesForParent(m_activeItemId, parentEntryId);
  if (m_submenuEntries.empty()) {
    return;
  }
  m_submenuParentEntryId = parentEntryId;
  // Signal the server that this submenu is being opened. Matches the opened/closed
  // pairing we do for the root menu.
  m_tray->notifyMenuOpened(m_activeItemId, parentEntryId);

  // Anchor rect is in the main popup's coordinate space (0,0 = top-left of main popup surface)
  const auto mainWidth = static_cast<std::int32_t>(m_instance->surface->width());
  const auto rowTop = static_cast<std::int32_t>(rowCenterY - Style::controlHeightSm * 0.5f);
  const auto rowH = static_cast<std::int32_t>(Style::controlHeightSm);
  constexpr std::int32_t kSubGap = 4;

  const auto surfaceWidth = static_cast<uint32_t>(kSurfaceWidth);
  const auto surfaceHeight = submenuHeightPx();

  const bool isRight = (m_instance->submenuDirection == ContextSubmenuDirection::Right);
  const std::int32_t anchorX = isRight ? mainWidth : 0;
  const std::uint32_t anchor = isRight ? XDG_POSITIONER_ANCHOR_TOP_RIGHT : XDG_POSITIONER_ANCHOR_TOP_LEFT;
  const std::uint32_t gravity = isRight ? XDG_POSITIONER_GRAVITY_BOTTOM_RIGHT : XDG_POSITIONER_GRAVITY_BOTTOM_LEFT;
  const std::int32_t offsetX = isRight ? kSubGap : -kSubGap;
  const auto subDir = isRight ? ContextSubmenuDirection::Right : ContextSubmenuDirection::Left;

  auto inst = std::make_unique<MenuInstance>();
  inst->output = m_instance->output;
  inst->surface = std::make_unique<PopupSurface>(*m_wayland);
  inst->submenuDirection = subDir;
  auto* instPtr = inst.get();

  inst->surface->setConfigureCallback([instPtr](uint32_t /*w*/, uint32_t /*h*/) { instPtr->surface->requestLayout(); });
  inst->surface->setPrepareFrameCallback(
      [this, instPtr](bool needsUpdate, bool needsLayout) { prepareSubmenuFrame(*instPtr, needsUpdate, needsLayout); });
  inst->surface->setDismissedCallback([this]() { closeSubmenu(); });
  inst->surface->setRenderContext(m_renderContext);

  auto popupConfig = PopupSurfaceConfig{
      .anchorX = anchorX,
      .anchorY = rowTop,
      .anchorWidth = 1,
      .anchorHeight = rowH,
      .width = surfaceWidth,
      .height = surfaceHeight,
      .anchor = anchor,
      .gravity = gravity,
      .constraintAdjustment = kPopupConstraintAdjust,
      .offsetX = offsetX,
      .offsetY = 0,
      .serial = m_wayland->lastInputSerial(),
      .grab = true,
  };

  xdg_surface* parentXdg = m_instance->surface->xdgSurface();
  if (!inst->surface->initializeAsChild(parentXdg, m_instance->output, popupConfig)) {
    kLog.warn("tray submenu: failed to create child popup surface");
    m_submenuEntries.clear();
    m_submenuParentEntryId = 0;
    return;
  }

  inst->wlSurface = inst->surface->wlSurface();
  m_submenuInstance = std::move(inst);
}

void TrayMenu::prepareSubmenuFrame(MenuInstance& inst, bool /*needsUpdate*/, bool needsLayout) {
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
                               static_cast<uint32_t>(std::round(inst.sceneRoot->width())) != width ||
                               static_cast<uint32_t>(std::round(inst.sceneRoot->height())) != height;
  if (needsSceneBuild || needsLayout) {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    buildSubmenuScene(inst, width, height);
  }
}

void TrayMenu::buildSubmenuScene(MenuInstance& inst, uint32_t width, uint32_t height) {
  uiAssertNotRendering("TrayMenu::buildSubmenuScene");
  const auto w = static_cast<float>(width);
  const auto h = static_cast<float>(height);

  inst.sceneRoot = std::make_unique<Node>();
  inst.sceneRoot->setSize(w, h);

  std::vector<ContextMenuControlEntry> entries;
  entries.reserve(m_submenuEntries.size());
  for (const auto& entry : m_submenuEntries) {
    entries.push_back(ContextMenuControlEntry{
        .id = entry.id,
        .label = entry.label,
        .enabled = entry.enabled,
        .separator = entry.separator,
        .hasSubmenu = entry.hasSubmenu,
    });
  }

  auto menu = std::make_unique<ContextMenuControl>();
  menu->setMenuWidth(w);
  menu->setMaxVisible(visibleEntryLimit(m_submenuEntries.size()));
  menu->setSubmenuDirection(inst.submenuDirection);
  menu->setEntries(std::move(entries));
  menu->setRedrawCallback([&inst]() {
    if (inst.surface != nullptr) {
      inst.surface->requestRedraw();
    }
  });
  menu->setOnActivate([this](const ContextMenuControlEntry& entry) {
    if (m_tray == nullptr || m_activeItemId.empty()) {
      return;
    }
    DeferredCall::callLater([this, entry]() {
      if (m_tray != nullptr) {
        (void)m_tray->activateMenuEntry(m_activeItemId, entry.id);
      }
      close();
    });
  });
  menu->setPosition(0.0f, 0.0f);
  menu->setSize(w, h);
  menu->layout(*m_renderContext);
  inst.sceneRoot->addChild(std::move(menu));

  inst.inputDispatcher.setSceneRoot(inst.sceneRoot.get());
  inst.inputDispatcher.setCursorShapeCallback(
      [this](uint32_t serial, uint32_t shape) { m_wayland->setCursorShape(serial, shape); });
  inst.surface->setSceneRoot(inst.sceneRoot.get());
}
