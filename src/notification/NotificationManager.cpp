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

void NotificationManager::setEventCallback(EventCallback callback) {
    m_event_callback = std::move(callback);
}

uint32_t NotificationManager::addOrReplace(uint32_t replaces_id,
                                            std::string app_name,
                                            std::string summary,
                                            std::string body,
                                            int32_t     timeout,
                                            Urgency     urgency) {
    if (replaces_id != 0) {
        if (const auto it = m_id_to_index.find(replaces_id); it != m_id_to_index.end()) {
            auto& n = m_notifications[it->second];
            n.app_name = std::move(app_name);
            n.summary  = std::move(summary);
            n.body     = std::move(body);
            n.timeout  = timeout;
            n.urgency  = urgency;

            std::cout << "[noctalia] updated #" << n.id
                      << " from=\""    << n.app_name << "\""
                      << " urgency="   << urgency_str(n.urgency)
                      << " summary=\""  << n.summary << "\""
                      << " body=\""    << n.body << "\""
                      << " timeout="   << n.timeout << "ms"
                      << '\n';

            if (m_event_callback) {
                m_event_callback(n, NotificationEvent::Updated);
            }

            return n.id;
        }
    }

    const uint32_t id = m_next_id++;
    m_notifications.push_back(Notification{
        .id       = id,
        .app_name = std::move(app_name),
        .summary  = std::move(summary),
        .body     = std::move(body),
        .timeout  = timeout,
        .urgency  = urgency,
    });
    m_id_to_index.emplace(id, m_notifications.size() - 1);

    const auto& n = m_notifications.back();
    std::cout << "[noctalia] added #" << n.id
              << " from=\""  << n.app_name << "\""
              << " urgency=" << urgency_str(n.urgency)
              << " summary=\"" << n.summary << "\""
              << " body=\""  << n.body << "\""
              << " timeout=" << n.timeout << "ms"
              << '\n';

    if (m_event_callback) {
        m_event_callback(n, NotificationEvent::Added);
    }

    return n.id;
}

const std::deque<Notification>& NotificationManager::all() const noexcept {
    return m_notifications;
}
