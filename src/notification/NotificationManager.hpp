#pragma once

#include "Notification.hpp"

#include <cstdint>
#include <deque>
#include <unordered_map>

class NotificationManager {
public:
    NotificationManager() = default;

    // Adds a new notification or updates an existing one.
    uint32_t addOrReplace(uint32_t replaces_id,
                          std::string app_name,
                          std::string summary,
                          std::string body,
                          int32_t     timeout,
                          Urgency     urgency);

    // All stored notifications.
    [[nodiscard]] const std::deque<Notification>& all() const noexcept;

private:
    std::deque<Notification>              m_notifications;
    std::unordered_map<uint32_t, size_t> m_id_to_index;
    uint32_t                              m_next_id{1};
};
