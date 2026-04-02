#pragma once

#include "Notification.hpp"

#include <cstdint>
#include <span>
#include <vector>

class NotificationManager {
public:
    NotificationManager() = default;

    // Stores a new notification and returns its assigned ID.
    uint32_t add(std::string app_name,
                 std::string summary,
                 std::string body,
                 int32_t     timeout,
                 Urgency     urgency);

    // All stored notifications.
    [[nodiscard]] std::span<const Notification> all() const noexcept;

private:
    std::vector<Notification> m_notifications;
    uint32_t                  m_next_id{1};
};
