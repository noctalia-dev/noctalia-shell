#include "shell/tray/tray_menu.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "dbus/tray/tray_service.h"
#include "render/render_context.h"
#include "ui/controls/context_menu.h"
#include "ui/style.h"
#include "wayland/layer_surface.h"
#include "wayland/wayland_connection.h"
#include "wayland/wayland_seat.h"

#include <algorithm>
#include <optional>
#include <string>

#include "xdg-shell-client-protocol.h"

namespace {

constexpr Logger kLog("tray");

constexpr float kMenuWidth = 246.0f;
constexpr std::size_t kMaxVisible = 14;

constexpr float kSurfaceWidth = kMenuWidth;

constexpr std::uint32_t kPopupConstraintAdjust = XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_X |
                                                 XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_Y |
                                                 XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_X |
                                                 XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_Y;

bool containsTrayWidget(const std::vector<std::string>& widgets) {
  return std::find(widgets.begin(), widgets.end(), "tray") != widgets.end();
}

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
  const std::int32_t iconSize = std::clamp(bar.height - 10, 16, 40);
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

  m_activeItemId = itemId;
  refreshEntries();

  m_visible = true;
  ensureSurface();
  if (m_instance == nullptr || m_instance->surface == nullptr) {
    close();
    return;
  }
  rebuildScenes();
}

void TrayMenu::close() {
  if (!m_visible) {
    return;
  }
  m_visible = false;
  closeSubmenu();
  destroySurface();
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
        if (onSub) sub->pointerInside = true;
        sub->inputDispatcher.pointerMotion(static_cast<float>(event.sx), static_cast<float>(event.sy), 0);
        subConsumed = true;
      }
      break;
    case PointerEvent::Type::Button:
      if (onSub || sub->pointerInside) {
        if (onSub) sub->pointerInside = true;
        const bool pressed = (event.state == 1);
        sub->inputDispatcher.pointerButton(static_cast<float>(event.sx), static_cast<float>(event.sy),
                                           event.button, pressed);
        subConsumed = true;
        if (m_submenuInstance == nullptr) {
          return subConsumed;
        }
      }
      break;
    case PointerEvent::Type::Axis:
      break;
    }

    if (sub->surface != nullptr && sub->sceneRoot != nullptr && sub->sceneRoot->dirty()) {
      sub->surface->requestRedraw();
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

  if (inst->surface != nullptr && inst->sceneRoot != nullptr && inst->sceneRoot->dirty()) {
    inst->surface->requestRedraw();
  }

  if (event.type == PointerEvent::Type::Button && event.state == 1 && !consumed) {
    close();
  }
  return consumed;
}

void TrayMenu::refreshEntries() {
  m_entries.clear();
  if (m_tray == nullptr || m_activeItemId.empty()) {
    return;
  }
  m_entries = m_tray->menuEntries(m_activeItemId);
  if (m_entries.empty()) {
    m_entries.push_back(TrayMenuEntry{
        .id = -1,
        .label = "No custom menu entries exposed",
        .enabled = false,
        .visible = true,
        .separator = false,
        .hasSubmenu = false,
    });
  }
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
  return static_cast<uint32_t>(ContextMenuControl::preferredHeight(entries, kMaxVisible));
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
  return static_cast<uint32_t>(ContextMenuControl::preferredHeight(entries, kMaxVisible));
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
    kLog.warn("tray menu: missing popup anchor context (parent={}, output={}, serial={})", parentLayerSurface != nullptr,
              output != nullptr, serial);
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
      [this, instPtr](uint32_t width, uint32_t height) { buildScene(*instPtr, width, height); });
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
  if (!m_visible || m_entries.empty() || m_instance == nullptr || m_instance->surface == nullptr) {
    return;
  }

  const std::uint32_t width = m_instance->surface->width() == 0 ? static_cast<uint32_t>(kSurfaceWidth) : m_instance->surface->width();
  const std::uint32_t height = m_instance->surface->height() == 0 ? surfaceHeightPx() : m_instance->surface->height();
  buildScene(*m_instance, width, height);
  m_instance->surface->requestRedraw();
}

void TrayMenu::buildScene(MenuInstance& inst, uint32_t width, uint32_t height) {
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
  menu->setMaxVisible(kMaxVisible);
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
  menu->setOnSubmenuOpen([this](const ContextMenuControlEntry& entry, float rowCenterY) {
    openSubmenu(entry.id, rowCenterY);
  });
  menu->setPosition(0.0f, 0.0f);
  menu->setSize(w, h);
  menu->rebuild(*m_renderContext);
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

  inst->surface->setConfigureCallback(
      [this, instPtr](uint32_t w, uint32_t h) { buildSubmenuScene(*instPtr, w, h); });
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

void TrayMenu::buildSubmenuScene(MenuInstance& inst, uint32_t width, uint32_t height) {
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
  menu->setMaxVisible(kMaxVisible);
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
  menu->rebuild(*m_renderContext);
  inst.sceneRoot->addChild(std::move(menu));

  inst.inputDispatcher.setSceneRoot(inst.sceneRoot.get());
  inst.inputDispatcher.setCursorShapeCallback(
      [this](uint32_t serial, uint32_t shape) { m_wayland->setCursorShape(serial, shape); });
  inst.surface->setSceneRoot(inst.sceneRoot.get());
}
