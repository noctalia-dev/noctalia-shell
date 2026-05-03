#pragma once

#include "notification.h"

#include <cstdint>
#include <deque>
#include <functional>
#include <optional>
#include <unordered_map>
#include <vector>

enum class NotificationEvent {
  Added,
  Updated,
  Closed,
};

struct NotificationHistoryEntry {
  Notification notification;
  bool active = true;
  std::optional<CloseReason> closeReason;
  std::uint64_t eventSerial = 0;
};

constexpr int32_t kDefaultNotificationTimeout = 6000;

class NotificationManager {
public:
  NotificationManager() = default;

  using EventCallback = std::function<void(const Notification&, NotificationEvent)>;
  using ActionInvokeCallback = std::function<void(uint32_t, const std::string&)>;
  using StateCallback = std::function<void()>;

  // Register a callback for notification events. Returns a token for removal.
  int addEventCallback(EventCallback callback);
  void removeEventCallback(int token);

  // Adds a new notification or updates an existing one.
  uint32_t addOrReplace(uint32_t replaces_id, std::string app_name, std::string summary, std::string body,
                        Urgency urgency, int32_t timeout, NotificationOrigin origin = NotificationOrigin::External,
                        std::vector<std::string> actions = {}, std::optional<std::string> icon = std::nullopt,
                        std::optional<NotificationImageData> image_data = std::nullopt,
                        std::optional<std::string> category = std::nullopt,
                        std::optional<std::string> desktop_entry = std::nullopt);

  // Adds an internal notification to the same store as external notifications.
  uint32_t addInternal(std::string app_name, std::string summary, std::string body, Urgency urgency = Urgency::Normal,
                       int32_t timeout = kDefaultNotificationTimeout, std::optional<std::string> icon = std::nullopt,
                       std::optional<NotificationImageData> image_data = std::nullopt,
                       std::optional<std::string> category = std::nullopt,
                       std::optional<std::string> desktop_entry = std::nullopt);

  void setActionInvokeCallback(ActionInvokeCallback callback);
  [[nodiscard]] bool invokeAction(uint32_t id, const std::string& actionKey, bool closeAfterInvoke = true);

  // Closes a notification by ID. Returns false if not found.
  bool close(uint32_t id, CloseReason reason = CloseReason::ClosedByCall);

  // Returns IDs of all notifications whose expiry_time has passed.
  [[nodiscard]] std::vector<uint32_t> expiredIds() const;

  // Returns ms until the next expiry, or -1 if none are scheduled.
  [[nodiscard]] int nextExpiryTimeoutMs() const;

  // Closes all expired notifications.
  void processExpired();

  // Pauses the expiry timer on a notification (clears its expiryTime). Used by the
  // toast to freeze the auto-dismiss while the user hovers a card.
  void pauseExpiry(uint32_t id);
  // Resumes expiry by setting expiryTime = now + remainingMs.
  void resumeExpiry(uint32_t id, int32_t remainingMs);

  // All stored notifications.
  [[nodiscard]] const std::deque<Notification>& all() const noexcept;

  // Recent notification history including closed notifications.
  [[nodiscard]] const std::deque<NotificationHistoryEntry>& history() const noexcept;
  [[nodiscard]] std::uint64_t changeSerial() const noexcept;
  void removeHistoryEntry(uint32_t id);
  void clearHistory();
  void setDoNotDisturb(bool enabled);
  [[nodiscard]] bool doNotDisturb() const noexcept;
  [[nodiscard]] bool toggleDoNotDisturb();
  void setStateCallback(StateCallback callback);
  void setSoundPlayer(class SoundPlayer* soundPlayer);

  // Bar indicator: true when at least one notification was added since the user last
  // viewed the notification history (control center notifications tab).
  [[nodiscard]] bool hasUnreadNotificationHistory() const noexcept;
  void markNotificationHistorySeen();

private:
  void upsertHistory(const Notification& notification, bool active, std::optional<CloseReason> closeReason);
  void rebuildHistoryIndex();

  std::deque<Notification> m_notifications;
  std::unordered_map<uint32_t, size_t> m_idToIndex;
  std::deque<NotificationHistoryEntry> m_history;
  std::unordered_map<uint32_t, size_t> m_historyIndex;
  std::vector<std::pair<int, EventCallback>> m_eventCallbacks;
  ActionInvokeCallback m_actionInvokeCallback;
  StateCallback m_stateCallback;
  int m_nextCallbackToken{0};
  uint32_t m_nextId{1};
  std::uint64_t m_changeSerial{0};
  bool m_doNotDisturb = false;
  bool m_unreadSinceHistoryVisit = false;
  class SoundPlayer* m_soundPlayer = nullptr;
};
