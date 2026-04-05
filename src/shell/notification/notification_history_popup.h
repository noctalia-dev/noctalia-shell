#pragma once

#include "notification/notification_manager.h"
#include "render/scene/input_dispatcher.h"
#include "render/scene/node.h"
#include "wayland/layer_surface.h"

#include <memory>
#include <vector>

class ConfigService;
class NotificationManager;
class RenderContext;
class WaylandConnection;
struct PointerEvent;
struct wl_surface;

class NotificationHistoryPopup {
public:
  NotificationHistoryPopup() = default;
  ~NotificationHistoryPopup();

  NotificationHistoryPopup(const NotificationHistoryPopup&) = delete;
  NotificationHistoryPopup& operator=(const NotificationHistoryPopup&) = delete;

  void initialize(WaylandConnection& wayland, ConfigService* config, NotificationManager* notifications,
                  RenderContext* renderContext);
  void toggleFromWidgetPress();
  void toggle();
  void close();

  [[nodiscard]] bool isVisible() const noexcept { return m_visible; }
  [[nodiscard]] bool onPointerEvent(const PointerEvent& event);

private:
  struct PopupInstance {
    wl_output* output = nullptr;
    std::int32_t scale = 1;

    std::unique_ptr<LayerSurface> surface;
    std::unique_ptr<Node> sceneRoot;
    InputDispatcher inputDispatcher;
    wl_surface* wlSurface = nullptr;
    bool pointerInside = false;
  };

  void refreshNotifications();
  void onNotificationEvent(const Notification& notification, NotificationEvent event);
  [[nodiscard]] bool ownsSurface(wl_surface* surface) const;
  [[nodiscard]] uint32_t surfaceHeightPx() const;
  void ensureSurfaces();
  void destroySurfaces();
  void rebuildScenes();
  void buildScene(PopupInstance& inst, uint32_t width, uint32_t height);

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  NotificationManager* m_notifications = nullptr;
  RenderContext* m_renderContext = nullptr;

  std::vector<Notification> m_items;
  std::vector<std::unique_ptr<PopupInstance>> m_instances;
  bool m_visible = false;
  bool m_ignoreNextOutsidePress = false;
  bool m_suppressRebuild = false;
  int m_callbackToken = -1;
};
