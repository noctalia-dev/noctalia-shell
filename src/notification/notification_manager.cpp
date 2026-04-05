#include "notification_manager.h"

#include "core/log.h"

#include <string_view>

namespace {

constexpr std::string_view urgency_str(Urgency u) noexcept {
  switch (u) {
  case Urgency::Low:
    return "low";
  case Urgency::Normal:
    return "normal";
  case Urgency::Critical:
    return "critical";
  }
  return "unknown";
}

constexpr std::string_view origin_str(NotificationOrigin o) noexcept {
  switch (o) {
  case NotificationOrigin::External:
    return "external";
  case NotificationOrigin::Internal:
    return "internal";
  }
  return "unknown";
}

std::optional<TimePoint> schedule_expiry(int32_t timeout_ms) noexcept {
  if (timeout_ms > 0) {
    return Clock::now() + std::chrono::milliseconds(timeout_ms);
  }
  return std::nullopt; // 0 = persistent, -1 = server default (treat as persistent for now)
}

} // namespace

int NotificationManager::addEventCallback(EventCallback callback) {
  int token = m_nextCallbackToken++;
  m_eventCallbacks.emplace_back(token, std::move(callback));
  return token;
}

void NotificationManager::removeEventCallback(int token) {
  std::erase_if(m_eventCallbacks, [token](const auto& pair) { return pair.first == token; });
}

uint32_t NotificationManager::addOrReplace(uint32_t replaces_id, std::string app_name, std::string summary,
                                           std::string body, int32_t timeout, Urgency urgency,
                                           NotificationOrigin origin, std::vector<std::string> actions,
                                           std::optional<std::string> icon, std::optional<std::string> category,
                                           std::optional<std::string> desktop_entry) {
  auto log_notification = [](const Notification& n, std::string_view action) {
    logDebug("notification {} #{} origin={} from=\"{}\" urgency={} summary=\"{}\" body=\"{}\" timeout={}ms", action,
             n.id, origin_str(n.origin), n.appName, urgency_str(n.urgency), n.summary, n.body, n.timeout);
  };

  if (replaces_id != 0) {
    if (const auto it = m_idToIndex.find(replaces_id); it != m_idToIndex.end()) {
      auto& n = m_notifications[it->second];

      // Check if anything changed to avoid duplicate events
      const bool changed = (n.appName != app_name || n.summary != summary || n.body != body || n.timeout != timeout ||
                            n.urgency != urgency || n.origin != origin || n.actions != actions || n.icon != icon ||
                            n.category != category || n.desktopEntry != desktop_entry);

      n.origin = origin;
      n.appName = std::move(app_name);
      n.summary = std::move(summary);
      n.body = std::move(body);
      n.timeout = timeout;
      n.urgency = urgency;
      n.actions = std::move(actions);
      n.icon = std::move(icon);
      n.category = std::move(category);
      n.desktopEntry = std::move(desktop_entry);
      n.expiryTime = schedule_expiry(timeout);

      log_notification(n, "updated");

      if (changed) {
        for (auto& [token, cb] : m_eventCallbacks) {
          cb(n, NotificationEvent::Updated);
        }
      }

      return n.id;
    }
  }

  const uint32_t id = m_nextId++;
  m_notifications.push_back(Notification{
      .id = id,
      .origin = origin,
      .appName = std::move(app_name),
      .summary = std::move(summary),
      .body = std::move(body),
      .timeout = timeout,
      .urgency = urgency,
      .actions = std::move(actions),
      .icon = std::move(icon),
      .category = std::move(category),
      .desktopEntry = std::move(desktop_entry),
      .expiryTime = schedule_expiry(timeout),
  });
  m_idToIndex.emplace(id, m_notifications.size() - 1);

  const auto& n = m_notifications.back();
  log_notification(n, "added");

  for (auto& [token, cb] : m_eventCallbacks) {
    cb(n, NotificationEvent::Added);
  }

  return n.id;
}

uint32_t NotificationManager::addInternal(std::string app_name, std::string summary, std::string body, int32_t timeout,
                                          Urgency urgency, std::optional<std::string> icon,
                                          std::optional<std::string> category,
                                          std::optional<std::string> desktop_entry) {
  return addOrReplace(0, std::move(app_name), std::move(summary), std::move(body), timeout, urgency,
                      NotificationOrigin::Internal, {}, std::move(icon), std::move(category), std::move(desktop_entry));
}

bool NotificationManager::close(uint32_t id, CloseReason reason) {
  const auto it = m_idToIndex.find(id);
  if (it == m_idToIndex.end()) {
    return false;
  }

  const size_t index = it->second;
  const Notification closed = m_notifications[index];
  const char* reason_str = (reason == CloseReason::Expired)     ? "expired"
                           : (reason == CloseReason::Dismissed) ? "dismissed"
                                                                : "closed";
  logDebug("notification {} #{}", reason_str, id);

  m_notifications.erase(m_notifications.begin() + static_cast<std::ptrdiff_t>(index));
  m_idToIndex.erase(it);

  for (size_t i = index; i < m_notifications.size(); ++i) {
    m_idToIndex[m_notifications[i].id] = i;
  }

  for (auto& [token, cb] : m_eventCallbacks) {
    cb(closed, NotificationEvent::Closed);
  }

  return true;
}

const std::deque<Notification>& NotificationManager::all() const noexcept { return m_notifications; }

std::vector<uint32_t> NotificationManager::expiredIds() const {
  const auto now = Clock::now();
  std::vector<uint32_t> ids;
  for (const auto& n : m_notifications) {
    if (n.expiryTime && now >= *n.expiryTime) {
      ids.push_back(n.id);
    }
  }
  return ids;
}

int NotificationManager::nextExpiryTimeoutMs() const {
  int expiry_ms = -1;
  const auto now = Clock::now();
  for (const auto& n : m_notifications) {
    if (n.expiryTime) {
      const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(*n.expiryTime - now).count();
      const int clamped = static_cast<int>(std::max<long long>(0, ms));
      if (expiry_ms < 0 || clamped < expiry_ms) {
        expiry_ms = clamped;
      }
    }
  }
  return expiry_ms;
}

void NotificationManager::processExpired() {
  for (const uint32_t id : expiredIds()) {
    close(id, CloseReason::Expired);
  }
}
