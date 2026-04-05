#pragma once

#include "dbus/tray/tray_service.h"
#include "render/scene/input_dispatcher.h"
#include "render/scene/node.h"
#include "wayland/layer_surface.h"

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
    std::int32_t scale = 1;

    std::unique_ptr<LayerSurface> surface;
    std::unique_ptr<Node> sceneRoot;
    InputDispatcher inputDispatcher;
    wl_surface* wlSurface = nullptr;
    bool pointerInside = false;
  };

  void refreshEntries();
  [[nodiscard]] uint32_t surfaceHeightPx() const;
  [[nodiscard]] bool ownsSurface(wl_surface* surface) const;
  void ensureSurfaces();
  void destroySurfaces();
  void rebuildScenes();
  void buildScene(MenuInstance& inst, uint32_t width, uint32_t height);

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  TrayService* m_tray = nullptr;
  RenderContext* m_renderContext = nullptr;

  std::string m_activeItemId;
  std::vector<TrayMenuEntry> m_entries;
  std::vector<std::unique_ptr<MenuInstance>> m_instances;
  bool m_visible = false;
};
