#pragma once

#include "notification/notification_manager.h"
#include "render/animation/animation_manager.h"
#include "render/scene/input_dispatcher.h"
#include "render/scene/node.h"
#include "ui/controls/label.h"
#include "ui/controls/progress_bar.h"
#include "wayland/layer_surface.h"
#include "wayland/surface.h"

#include <memory>
#include <vector>

class ConfigService;
class Glyph;
class InputArea;
class RenderContext;
class WaylandConnection;
struct PointerEvent;

class NotificationToast {
public:
  NotificationToast();
  ~NotificationToast();

  NotificationToast(const NotificationToast&) = delete;
  NotificationToast& operator=(const NotificationToast&) = delete;

  void initialize(WaylandConnection& wayland, ConfigService* config, NotificationManager* notifications,
                  RenderContext* renderContext);
  void requestRedraw();

  bool onPointerEvent(const PointerEvent& event);

private:
  // Per-notification visual state (shared across all instances)
  struct PopupEntry {
    uint32_t notificationId = 0;
    std::string appName;
    std::string summary;
    std::string body;
    Urgency urgency = Urgency::Normal;
    int displayDurationMs = 0; // -1 = persistent (no auto-dismiss)
    float remainingProgress = 1.0f;
    std::size_t slot = 0;         // stable visual slot index; entries keep their slot while hovered
    bool exiting = false;
    bool hovered = false; // pointer is currently over the card on some instance
  };

  // Per-output instance (each has its own surface, scene, animations)
  struct PopupInstance {
    wl_output* output = nullptr;
    std::int32_t scale = 1;

    std::unique_ptr<LayerSurface> surface;
    // Declaration order matters: sceneRoot must be destroyed before `animations`,
    // because ~Node() calls cancelForOwner() on its AnimationManager.
    AnimationManager animations;
    std::unique_ptr<Node> sceneRoot;
    InputDispatcher inputDispatcher;
    bool pointerInside = false;

    // Per-entry visual nodes for this instance
    struct CardState {
      Node* cardNode = nullptr;
      Node* cardBg = nullptr;
      Label* appNameLabel = nullptr;
      Label* summaryLabel = nullptr;
      Label* bodyLabel = nullptr;
      ProgressBar* progressBar = nullptr;
      Glyph* closeGlyph = nullptr;
      AnimationManager::Id countdownAnimId = 0;
      AnimationManager::Id entryAnimId = 0;
      AnimationManager::Id slideAnimId = 0;
      AnimationManager::Id exitAnimId = 0;
    };
    std::vector<CardState> cards;
    float lastPointerX = 0.0f;
    float lastPointerY = 0.0f;
  };

  void onNotificationEvent(const Notification& n, NotificationEvent event);
  void addPopup(const Notification& n);
  void dismissPopup(std::size_t index);
  void removePopup(uint32_t notificationId);
  void finishRemoval(uint32_t notificationId);
  void layoutCards(PopupInstance& inst);
  void updateInputRegion(PopupInstance& inst) const;

  void ensureSurfaces();
  void destroySurfaces();
  void prepareFrame(PopupInstance& inst, bool needsUpdate, bool needsLayout);
  void buildScene(PopupInstance& inst, uint32_t width, uint32_t height);
  InputArea* buildCard(const PopupEntry& entry, Label** outAppName, Label** outSummary, Label** outBody,
                       Node** outBg, ProgressBar** outProgress, Glyph** outCloseGlyph);
  void addCardToInstance(PopupInstance& inst, std::size_t entryIndex);
  void dismissCardFromInstance(PopupInstance& inst, std::size_t entryIndex);

  float cardTargetY(std::size_t slot) const;
  PopupEntry* findEntry(uint32_t notificationId);
  PopupInstance::CardState* findCardState(PopupInstance& inst, uint32_t notificationId);
  void pauseCountdowns(uint32_t notificationId);
  void resumeCountdowns(uint32_t notificationId);
  void revealQueuedEntries();
  std::size_t findFreeSlot() const;

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  NotificationManager* m_notifications = nullptr;
  RenderContext* m_renderContext = nullptr;

  std::vector<PopupEntry> m_entries;
  std::vector<std::unique_ptr<PopupInstance>> m_instances;
  int m_callbackToken = -1;
};
