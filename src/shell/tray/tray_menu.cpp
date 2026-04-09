#include "shell/tray/tray_menu.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "render/render_context.h"
#include "render/scene/input_area.h"
#include "ui/controls/box.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/wayland_connection.h"
#include "wayland/wayland_seat.h"

#include <algorithm>
#include <linux/input-event-codes.h>
#include <string>

namespace {

constexpr Logger kLog("tray");

constexpr float kMenuWidth = 320.0f;
constexpr float kMenuPadding = 10.0f;
constexpr float kItemHeight = 30.0f;
constexpr float kItemGap = 4.0f;
constexpr std::size_t kMaxVisible = 14;

constexpr float kSurfaceWidth = kMenuWidth;

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
  ensureSurfaces();
  rebuildScenes();
}

void TrayMenu::close() {
  if (!m_visible) {
    return;
  }
  m_visible = false;
  destroySurfaces();
}

bool TrayMenu::onPointerEvent(const PointerEvent& event) {
  if (!m_visible) {
    return false;
  }

  if (event.type == PointerEvent::Type::Button && event.state == 1 && !ownsSurface(event.surface)) {
    close();
    return false;
  }

  bool consumed = false;
  for (std::size_t i = 0; i < m_instances.size(); ++i) {
    auto* inst = m_instances[i].get();
    if (inst == nullptr) {
      continue;
    }

    switch (event.type) {
    case PointerEvent::Type::Enter:
      if (event.surface == inst->wlSurface) {
        inst->pointerInside = true;
        inst->inputDispatcher.pointerEnter(static_cast<float>(event.sx), static_cast<float>(event.sy), event.serial);
      }
      break;
    case PointerEvent::Type::Leave:
      if (event.surface == inst->wlSurface) {
        inst->pointerInside = false;
        inst->inputDispatcher.pointerLeave();
      }
      break;
    case PointerEvent::Type::Motion:
      if (inst->pointerInside) {
        inst->inputDispatcher.pointerMotion(static_cast<float>(event.sx), static_cast<float>(event.sy), 0);
        consumed = true;
      }
      break;
    case PointerEvent::Type::Button:
      if (inst->pointerInside) {
        bool pressed = (event.state == 1);
        inst->inputDispatcher.pointerButton(static_cast<float>(event.sx), static_cast<float>(event.sy), event.button,
                                            pressed);
        consumed = true;
        if (!m_visible || m_instances.empty()) {
          return consumed;
        }
      }
      break;
    case PointerEvent::Type::Axis:
      break;
    }

    if (event.type == PointerEvent::Type::Button) {
      continue;
    }
    if (inst->surface != nullptr && inst->sceneRoot != nullptr && inst->sceneRoot->dirty()) {
      inst->surface->requestRedraw();
    }
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

uint32_t TrayMenu::surfaceHeightPx() const {
  const std::size_t visibleEntries = std::min(m_entries.size(), kMaxVisible);
  if (visibleEntries == 0) {
    return static_cast<uint32_t>(kMenuPadding * 2);
  }

  const float height = kMenuPadding * 2 + kItemHeight * static_cast<float>(visibleEntries) +
                       kItemGap * static_cast<float>(visibleEntries - 1);
  return static_cast<uint32_t>(height);
}

bool TrayMenu::ownsSurface(wl_surface* surface) const {
  if (surface == nullptr) {
    return false;
  }

  return std::any_of(m_instances.begin(), m_instances.end(),
                     [surface](const auto& inst) { return inst != nullptr && inst->wlSurface == surface; });
}

void TrayMenu::ensureSurfaces() {
  if (!m_instances.empty()) {
    return;
  }
  if (m_wayland == nullptr || m_renderContext == nullptr) {
    return;
  }

  std::uint32_t barHeight = Style::barHeightDefault;
  if (m_config != nullptr && !m_config->config().bars.empty()) {
    barHeight = m_config->config().bars[0].height;
  }

  auto surfaceWidth = static_cast<uint32_t>(kSurfaceWidth);
  auto surfaceHeight = surfaceHeightPx();

  for (const auto& output : m_wayland->outputs()) {
    auto inst = std::make_unique<MenuInstance>();
    inst->output = output.output;
    inst->scale = output.scale;

    auto surfaceConfig = LayerSurfaceConfig{
        .nameSpace = "noctalia-tray-menu",
        .layer = LayerShellLayer::Top,
        .anchor = LayerShellAnchor::Top | LayerShellAnchor::Right,
        .width = surfaceWidth,
        .height = surfaceHeight,
        .exclusiveZone = 0,
        .marginTop = static_cast<std::int32_t>(barHeight) + 4,
        .marginRight = 8,
        .keyboard = LayerShellKeyboard::None,
        .defaultWidth = surfaceWidth,
        .defaultHeight = surfaceHeight,
    };

    inst->surface = std::make_unique<LayerSurface>(*m_wayland, std::move(surfaceConfig));
    auto* instPtr = inst.get();
    inst->surface->setConfigureCallback(
        [this, instPtr](uint32_t width, uint32_t height) { buildScene(*instPtr, width, height); });
    inst->surface->setRenderContext(m_renderContext);

    bool ok = inst->surface->initialize(output.output, output.scale);
    if (!ok) {
      kLog.warn("tray menu: failed to initialize surface on {}", output.connectorName);
      continue;
    }

    inst->wlSurface = inst->surface->wlSurface();
    m_instances.push_back(std::move(inst));
  }
}

void TrayMenu::destroySurfaces() {
  for (auto& inst : m_instances) {
    inst->inputDispatcher.setSceneRoot(nullptr);
  }
  m_instances.clear();
}

void TrayMenu::rebuildScenes() {
  if (!m_visible || m_entries.empty()) {
    return;
  }

  for (auto& inst : m_instances) {
    buildScene(*inst, static_cast<uint32_t>(kSurfaceWidth), surfaceHeightPx());
    if (inst->surface != nullptr) {
      inst->surface->requestRedraw();
    }
  }
}

void TrayMenu::buildScene(MenuInstance& inst, uint32_t width, uint32_t height) {
  auto w = static_cast<float>(width);
  auto h = static_cast<float>(height);

  inst.sceneRoot = std::make_unique<Node>();
  inst.sceneRoot->setSize(w, h);

  auto bg = std::make_unique<Box>();
  bg->setCardStyle();
  bg->setSize(w, h);
  inst.sceneRoot->addChild(std::move(bg));

  const std::size_t visibleItems = std::min(m_entries.size(), kMaxVisible);
  const float rowWidth = kMenuWidth - kMenuPadding * 2;
  const float rowsTop = kMenuPadding;

  for (std::size_t i = 0; i < visibleItems; ++i) {
    const TrayMenuEntry& entry = m_entries[i];

    auto row = std::make_unique<InputArea>();
    row->setSize(rowWidth, kItemHeight);
    row->setPosition(kMenuPadding, rowsTop + static_cast<float>(i) * (kItemHeight + kItemGap));
    row->setOnClick([this, entry](const InputArea::PointerData& data) {
      if (m_tray == nullptr || m_activeItemId.empty() || !entry.enabled || entry.separator) {
        return;
      }
      if (data.button == BTN_LEFT) {
        DeferredCall::callLater([this, entry]() {
          if (m_tray != nullptr) {
            (void)m_tray->activateMenuEntry(m_activeItemId, entry.id);
          }
          close();
        });
      }
    });

    if (!entry.separator) {
      auto rowBg = std::make_unique<Box>();
      rowBg->setFill(palette.surfaceVariant);
      rowBg->setRadius(Style::radiusSm);
      rowBg->setSize(rowWidth, kItemHeight);
      row->addChild(std::move(rowBg));

      std::string labelText = entry.label;
      if (entry.hasSubmenu) {
        labelText += "  >";
      }
      auto label = std::make_unique<Label>();
      label->setText(labelText);
      label->setFontSize(Style::fontSizeBody);
      label->setColor(entry.enabled ? palette.onSurface : palette.onSurfaceVariant);
      label->setMaxWidth(rowWidth - 20.0f);
      label->measure(*m_renderContext);
      label->setPosition(10.0f, (kItemHeight - label->height()) * 0.5f);
      row->addChild(std::move(label));
    } else {
      auto separator = std::make_unique<Box>();
      separator->setFill(palette.outline);
      separator->setSize(rowWidth - 12.0f, 1.0f);
      separator->setPosition(6.0f, (kItemHeight - 1.0f) * 0.5f);
      row->addChild(std::move(separator));
    }

    inst.sceneRoot->addChild(std::move(row));
  }

  inst.inputDispatcher.setSceneRoot(inst.sceneRoot.get());
  inst.inputDispatcher.setCursorShapeCallback(
      [this](uint32_t serial, uint32_t shape) { m_wayland->setCursorShape(serial, shape); });
  inst.surface->setSceneRoot(inst.sceneRoot.get());
}
