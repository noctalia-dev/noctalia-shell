#pragma once

#include "core/timer_manager.h"
#include "dbus/tray/tray_service.h"
#include "render/scene/input_dispatcher.h"
#include "render/scene/node.h"
#include "ui/controls/context_menu.h"
#include "wayland/popup_surface.h"

#include <chrono>
#include <memory>
#include <string>
#include <vector>

class ConfigService;
class RenderContext;
class WaylandConnection;
struct PointerEvent;
struct wl_surface;

class TrayMenu {
public:
  TrayMenu() = default;

  void initialize(WaylandConnection& wayland, ConfigService* config, TrayService* tray, RenderContext* renderContext);
  void onTrayChanged();

  void toggleForItem(const std::string& itemId);
  void close();
  void onThemeChanged();

  [[nodiscard]] bool onPointerEvent(const PointerEvent& event);

private:
  struct MenuInstance {
    wl_output* output = nullptr;
    std::unique_ptr<PopupSurface> surface;
    std::unique_ptr<Node> sceneRoot;
    InputDispatcher inputDispatcher;
    wl_surface* wlSurface = nullptr;
    bool pointerInside = false;
    ContextSubmenuDirection submenuDirection = ContextSubmenuDirection::Right;
  };

  void refreshEntries();
  void scheduleEntryRetry(int attempt);
  [[nodiscard]] uint32_t surfaceHeightPx() const;
  [[nodiscard]] uint32_t submenuHeightPx() const;
  [[nodiscard]] bool ownsSurface(wl_surface* surface) const;
  void ensureSurface();
  void destroySurface();
  void rebuildScenes();
  void prepareMainMenuFrame(MenuInstance& inst, bool needsUpdate, bool needsLayout);
  void buildScene(MenuInstance& inst, uint32_t width, uint32_t height);
  void openSubmenu(std::int32_t parentEntryId, float rowCenterY);
  void closeSubmenu();
  void prepareSubmenuFrame(MenuInstance& inst, bool needsUpdate, bool needsLayout);
  void buildSubmenuScene(MenuInstance& inst, uint32_t width, uint32_t height);

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  TrayService* m_tray = nullptr;
  RenderContext* m_renderContext = nullptr;

  std::string m_activeItemId;
  std::vector<TrayMenuEntry> m_entries;
  std::unique_ptr<MenuInstance> m_instance;
  bool m_visible = false;
  std::string m_lastClosedItemId;
  std::chrono::steady_clock::time_point m_lastCloseTime;

  // Pre-warmed entries: populated by a background retry while the menu is closed,
  // so the next open for the same item skips the D-Bus round-trip.
  std::string m_preWarmedItemId;
  std::vector<TrayMenuEntry> m_preWarmedEntries;

  std::vector<TrayMenuEntry> m_submenuEntries;
  std::int32_t m_submenuParentEntryId = 0;
  std::unique_ptr<MenuInstance> m_submenuInstance;

  Timer m_retryTimer;
};
