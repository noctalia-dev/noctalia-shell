#pragma once

#include "Notification.h"

#include <cstdint>
#include <deque>
#include <functional>
#include <unordered_map>
#include <vector>

enum class NotificationEvent {
  Added,
  Updated,
};

class NotificationManager {
public:
  NotificationManager() = default;

  using EventCallback = std::function<void(const Notification&, NotificationEvent)>;

  // Sets a callback for add or update events.
  void setEventCallback(EventCallback callback);

  // Adds a new notification or updates an existing one.
  uint32_t addOrReplace(uint32_t replaces_id, std::string app_name, std::string summary, std::string body,
                        int32_t timeout, Urgency urgency, NotificationOrigin origin = NotificationOrigin::External,
                        std::vector<std::string> actions = {}, std::optional<std::string> icon = std::nullopt,
                        std::optional<std::string> category = std::nullopt,
                        std::optional<std::string> desktop_entry = std::nullopt);

  // Adds an internal notification to the same store as external notifications.
  uint32_t addInternal(std::string app_name, std::string summary, std::string body, int32_t timeout,
                       Urgency urgency = Urgency::Normal, std::optional<std::string> icon = std::nullopt,
                       std::optional<std::string> category = std::nullopt,
                       std::optional<std::string> desktop_entry = std::nullopt);

  // Closes a notification by ID. Returns false if not found.
  bool close(uint32_t id, CloseReason reason = CloseReason::ClosedByCall);

  // Returns IDs of all notifications whose expiry_time has passed.
  [[nodiscard]] std::vector<uint32_t> expiredIds() const;

  // All stored notifications.
  [[nodiscard]] const std::deque<Notification>& all() const noexcept;

private:
  std::deque<Notification> m_notifications;
  std::unordered_map<uint32_t, size_t> m_id_to_index;
  EventCallback m_event_callback;
  uint32_t m_next_id{1};
};
