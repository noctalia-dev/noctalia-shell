#pragma once

#include "dbus/tray/tray_service.h"
#include "render/scene/input_dispatcher.h"
#include "render/scene/node.h"
#include "ui/controls/context_menu.h"
#include "wayland/popup_surface.h"

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
  [[nodiscard]] uint32_t surfaceHeightPx() const;
  [[nodiscard]] uint32_t submenuHeightPx() const;
  [[nodiscard]] bool ownsSurface(wl_surface* surface) const;
  void ensureSurface();
  void destroySurface();
  void rebuildScenes();
  void buildScene(MenuInstance& inst, uint32_t width, uint32_t height);
  void openSubmenu(std::int32_t parentEntryId, float rowCenterY);
  void closeSubmenu();
  void buildSubmenuScene(MenuInstance& inst, uint32_t width, uint32_t height);

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  TrayService* m_tray = nullptr;
  RenderContext* m_renderContext = nullptr;

  std::string m_activeItemId;
  std::vector<TrayMenuEntry> m_entries;
  std::unique_ptr<MenuInstance> m_instance;
  bool m_visible = false;

  std::vector<TrayMenuEntry> m_submenuEntries;
  std::int32_t m_submenuParentEntryId = 0;
  std::unique_ptr<MenuInstance> m_submenuInstance;
};
