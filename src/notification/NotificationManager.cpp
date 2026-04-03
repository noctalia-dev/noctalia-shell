#include "NotificationManager.hpp"

#include "core/Log.hpp"

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

std::optional<TimePoint> schedule_expiry(int32_t timeout_ms) noexcept {
    if (timeout_ms > 0) {
        return Clock::now() + std::chrono::milliseconds(timeout_ms);
    }
    return std::nullopt;  // 0 = persistent, -1 = server default (treat as persistent for now)
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
                                            Urgency     urgency,
                                            std::optional<std::string> icon,
                                            std::optional<std::string> category,
                                            std::optional<std::string> desktop_entry) {
    auto log_notification = [](const Notification& n, std::string_view action) {
        logDebug("notification {} #{} from=\"{}\" urgency={} summary=\"{}\" body=\"{}\" timeout={}ms",
            action, n.id, n.app_name, urgency_str(n.urgency), n.summary, n.body, n.timeout);
    };

    if (replaces_id != 0) {
        if (const auto it = m_id_to_index.find(replaces_id); it != m_id_to_index.end()) {
            auto& n = m_notifications[it->second];
            n.app_name = std::move(app_name);
            n.summary  = std::move(summary);
            n.body     = std::move(body);
            n.timeout  = timeout;
            n.urgency  = urgency;
            n.icon     = std::move(icon);
            n.category = std::move(category);
            n.desktop_entry = std::move(desktop_entry);
            n.expiry_time   = schedule_expiry(timeout);

            log_notification(n, "updated");

            if (m_event_callback) {
                m_event_callback(n, NotificationEvent::Updated);
            }

            return n.id;
        }
    }

    const uint32_t id = m_next_id++;
    m_notifications.push_back(Notification{
        .id            = id,
        .app_name      = std::move(app_name),
        .summary       = std::move(summary),
        .body          = std::move(body),
        .timeout       = timeout,
        .urgency       = urgency,
        .icon          = std::move(icon),
        .category      = std::move(category),
        .desktop_entry = std::move(desktop_entry),
        .expiry_time   = schedule_expiry(timeout),
    });
    m_id_to_index.emplace(id, m_notifications.size() - 1);

    const auto& n = m_notifications.back();
    log_notification(n, "added");

    if (m_event_callback) {
        m_event_callback(n, NotificationEvent::Added);
    }

    return n.id;
}

bool NotificationManager::close(uint32_t id, CloseReason reason) {
    const auto it = m_id_to_index.find(id);
    if (it == m_id_to_index.end()) {
        return false;
    }

    const size_t index = it->second;
    const char* reason_str = (reason == CloseReason::Expired) ? "expired" :
                             (reason == CloseReason::Dismissed) ? "dismissed" : "closed";
    logDebug("notification {} #{}", reason_str, id);

    m_notifications.erase(m_notifications.begin() + static_cast<std::ptrdiff_t>(index));
    m_id_to_index.erase(it);

    for (size_t i = index; i < m_notifications.size(); ++i) {
        m_id_to_index[m_notifications[i].id] = i;
    }

    return true;
}

const std::deque<Notification>& NotificationManager::all() const noexcept {
    return m_notifications;
}

std::vector<uint32_t> NotificationManager::expiredIds() const {
    const auto now = Clock::now();
    std::vector<uint32_t> ids;
    for (const auto& n : m_notifications) {
        if (n.expiry_time && now >= *n.expiry_time) {
            ids.push_back(n.id);
        }
    }
    return ids;
}
