#include "NotificationManager.hpp"

#include <iostream>
#include <string_view>

namespace {

constexpr std::string_view urgency_str(Urgency u) noexcept {
    switch (u) {
        case Urgency::Low:      return "low";
        case Urgency::Normal:   return "normal";
        case Urgency::Critical: return "critical";
    }
    return "unknown";
}

}

uint32_t NotificationManager::add(std::string app_name,
                                   std::string summary,
                                   std::string body,
                                   int32_t     timeout,
                                   Urgency     urgency) {
    const uint32_t id = m_next_id++;

    m_notifications.push_back(Notification{
        .id       = id,
        .app_name = std::move(app_name),
        .summary  = std::move(summary),
        .body     = std::move(body),
        .timeout  = timeout,
        .urgency  = urgency,
    });

    const auto& n = m_notifications.back();
    std::cout << "[noctalia] notification #" << n.id
              << " from=\""   << n.app_name << "\""
              << " urgency="  << urgency_str(n.urgency)
              << " summary=\"" << n.summary << "\""
              << " body=\""   << n.body << "\""
              << " timeout="  << n.timeout << "ms"
              << '\n';

    return id;
}

std::span<const Notification> NotificationManager::all() const noexcept {
    return m_notifications;
}
