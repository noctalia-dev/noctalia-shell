#pragma once

#include "notification/notification_manager.h"
#include "render/animation/animation_manager.h"
#include "render/scene/input_dispatcher.h"
#include "render/scene/node.h"
#include "wayland/layer_surface.h"

#include <memory>
#include <vector>

class ConfigService;
class RectNode;
class RenderContext;
class WaylandConnection;
struct PointerEvent;
struct wl_surface;

class NotificationPopup {
public:
  NotificationPopup();
  ~NotificationPopup();

  NotificationPopup(const NotificationPopup&) = delete;
  NotificationPopup& operator=(const NotificationPopup&) = delete;

  void initialize(WaylandConnection& wayland, ConfigService* config, NotificationManager* notifications,
                  RenderContext* renderContext);

  bool onPointerEvent(const PointerEvent& event);

private:
  // Per-notification visual state (shared across all instances)
  struct PopupEntry {
    uint32_t notificationId = 0;
    std::string appName;
    std::string summary;
    std::string body;
    std::string wrappedSummary;
    std::string wrappedBody;
    std::size_t summaryLines = 1;
    std::size_t bodyLines = 1;
    float cardHeight = 0.0f;
    Urgency urgency = Urgency::Normal;
    bool exiting = false;
  };

  // Per-output instance (each has its own surface, scene, animations)
  struct PopupInstance {
    wl_output* output = nullptr;
    std::int32_t scale = 1;

    std::unique_ptr<LayerSurface> surface;
    std::unique_ptr<Node> sceneRoot;
    AnimationManager animations;
    InputDispatcher inputDispatcher;
    wl_surface* wlSurface = nullptr;
    bool pointerInside = false;

    // Per-entry visual nodes for this instance
    struct CardState {
      Node* cardNode = nullptr;
      RectNode* progressFill = nullptr;
      AnimationManager::Id countdownAnimId = 0;
      AnimationManager::Id entryAnimId = 0;
      AnimationManager::Id slideAnimId = 0;
    };
    std::vector<CardState> cards;
  };

  void onNotificationEvent(const Notification& n, NotificationEvent event);
  void addPopup(const Notification& n);
  void dismissPopup(std::size_t index);
  void removePopup(uint32_t notificationId);
  void finishRemoval(std::size_t index);
  void layoutCards(PopupInstance& inst);

  void ensureSurfaces();
  void destroySurfaces();
  void buildScene(PopupInstance& inst, uint32_t width, uint32_t height);
  Node* buildCard(const PopupEntry& entry);
  void addCardToInstance(PopupInstance& inst, std::size_t entryIndex);
  void dismissCardFromInstance(PopupInstance& inst, std::size_t entryIndex);

  float cardTargetY(std::size_t index) const;
  void updateEntryLayout(PopupEntry& entry) const;

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  NotificationManager* m_notifications = nullptr;
  RenderContext* m_renderContext = nullptr;

  std::vector<PopupEntry> m_entries;
  std::vector<std::unique_ptr<PopupInstance>> m_instances;
  int m_callbackToken = -1;
};
