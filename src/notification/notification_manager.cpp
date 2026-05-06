#include "notification_manager.h"

#include "core/deferred_call.h"
#include "core/log.h"
#include "notification/notification_history_store.h"
#include "pipewire/sound_player.h"
#include "util/file_utils.h"

#include <filesystem>
#include <string_view>

namespace {

  constexpr Logger kLog("notification");
  constexpr auto kImplicitDuplicateWindow = std::chrono::seconds(1);

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

  std::optional<TimePoint> schedule_expiry(TimePoint now, int32_t timeout_ms) noexcept {
    if (timeout_ms > 0) {
      return now + std::chrono::milliseconds(timeout_ms);
    }
    return std::nullopt; // 0 = persistent, -1 = server default (treat as persistent for now)
  }

  std::optional<WallTimePoint> schedule_expiry_wall(WallTimePoint wallNow, int32_t timeout_ms) noexcept {
    if (timeout_ms > 0) {
      return wallNow + std::chrono::milliseconds(timeout_ms);
    }
    return std::nullopt;
  }

  bool has_same_content(const Notification& notification, const std::string& appName, const std::string& summary,
                        const std::string& body) {
    return notification.appName == appName && notification.summary == summary && notification.body == body;
  }

} // namespace

void NotificationManager::rebuildHistoryIndex() {
  m_historyIndex.clear();
  for (size_t i = 0; i < m_history.size(); ++i) {
    m_historyIndex[m_history[i].notification.id] = i;
  }
}

void NotificationManager::upsertHistory(const Notification& notification, bool active,
                                        std::optional<CloseReason> closeReason) {
  if (const auto it = m_historyIndex.find(notification.id); it != m_historyIndex.end()) {
    m_history.erase(m_history.begin() + static_cast<std::ptrdiff_t>(it->second));
  }

  m_history.push_back(NotificationHistoryEntry{
      .notification = notification,
      .active = active,
      .closeReason = closeReason,
      .eventSerial = ++m_changeSerial,
  });

  constexpr std::size_t kMaxHistoryEntries = 100;
  while (m_history.size() > kMaxHistoryEntries) {
    m_history.pop_front();
  }

  rebuildHistoryIndex();
  schedulePersistHistory();
}

int NotificationManager::addEventCallback(EventCallback callback) {
  int token = m_nextCallbackToken++;
  m_eventCallbacks.emplace_back(token, std::move(callback));
  return token;
}

void NotificationManager::removeEventCallback(int token) {
  std::erase_if(m_eventCallbacks, [token](const auto& pair) { return pair.first == token; });
}

uint32_t NotificationManager::addOrReplace(uint32_t replaces_id, std::string app_name, std::string summary,
                                           std::string body, Urgency urgency, int32_t timeout,
                                           NotificationOrigin origin, std::vector<std::string> actions,
                                           std::optional<std::string> icon,
                                           std::optional<NotificationImageData> image_data,
                                           std::optional<std::string> category,
                                           std::optional<std::string> desktop_entry) {
  const auto now = Clock::now();
  const auto wallNow = WallClock::now();
  auto log_notification = [](const Notification& n, std::string_view action) {
    kLog.debug("notification {} #{} origin={} from=\"{}\" urgency={} summary=\"{}\" body=\"{}\" timeout={}ms", action,
               n.id, origin_str(n.origin), n.appName, urgency_str(n.urgency), n.summary, n.body, n.timeout);
  };

  if (replaces_id != 0) {
    if (const auto it = m_idToIndex.find(replaces_id); it != m_idToIndex.end()) {
      auto& n = m_notifications[it->second];

      // Check if anything changed to avoid duplicate events
      const bool changed = (n.appName != app_name || n.summary != summary || n.body != body || n.timeout != timeout ||
                            n.urgency != urgency || n.origin != origin || n.actions != actions || n.icon != icon ||
                            n.imageData != image_data || n.category != category || n.desktopEntry != desktop_entry);

      n.origin = origin;
      n.appName = std::move(app_name);
      n.summary = std::move(summary);
      n.body = std::move(body);
      n.timeout = timeout;
      n.urgency = urgency;
      n.actions = std::move(actions);
      n.icon = std::move(icon);
      n.imageData = std::move(image_data);
      n.category = std::move(category);
      n.desktopEntry = std::move(desktop_entry);
      n.receivedTime = now;
      n.expiryTime = schedule_expiry(now, timeout);
      n.receivedWallClock = wallNow;
      n.expiryWallClock = schedule_expiry_wall(wallNow, timeout);

      log_notification(n, "updated");
      upsertHistory(n, true, std::nullopt);

      if (changed) {
        for (auto& [token, cb] : m_eventCallbacks) {
          cb(n, NotificationEvent::Updated);
        }
      }

      return n.id;
    }
  }

  // Suppress immediate duplicate bursts. Later same-content notifications should still be visible.
  for (auto it = m_notifications.rbegin(); it != m_notifications.rend(); ++it) {
    const auto& existing = *it;
    if (has_same_content(existing, app_name, summary, body) && now - existing.receivedTime < kImplicitDuplicateWindow) {
      log_notification(existing, "duplicate ignored");
      return existing.id;
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
      .imageData = std::move(image_data),
      .category = std::move(category),
      .desktopEntry = std::move(desktop_entry),
      .receivedTime = now,
      .expiryTime = schedule_expiry(now, timeout),
      .receivedWallClock = wallNow,
      .expiryWallClock = schedule_expiry_wall(wallNow, timeout),
  });
  m_idToIndex.emplace(id, m_notifications.size() - 1);

  const auto& n = m_notifications.back();
  log_notification(n, "added");
  upsertHistory(n, true, std::nullopt);
  m_unreadSinceHistoryVisit = true;

  for (auto& [token, cb] : m_eventCallbacks) {
    cb(n, NotificationEvent::Added);
  }
  if (!m_doNotDisturb && m_soundPlayer != nullptr) {
    m_soundPlayer->play("notification");
  }

  return n.id;
}

uint32_t NotificationManager::addInternal(std::string app_name, std::string summary, std::string body, Urgency urgency,
                                          int32_t timeout, std::optional<std::string> icon,
                                          std::optional<NotificationImageData> image_data,
                                          std::optional<std::string> category,
                                          std::optional<std::string> desktop_entry) {
  return addOrReplace(0, std::move(app_name), std::move(summary), std::move(body), urgency, timeout,
                      NotificationOrigin::Internal, {}, std::move(icon), std::move(image_data), std::move(category),
                      std::move(desktop_entry));
}

void NotificationManager::setActionInvokeCallback(ActionInvokeCallback callback) {
  m_actionInvokeCallback = std::move(callback);
}

bool NotificationManager::invokeAction(uint32_t id, const std::string& actionKey, bool closeAfterInvoke) {
  const auto it = m_idToIndex.find(id);
  if (it == m_idToIndex.end() || actionKey.empty()) {
    return false;
  }

  const Notification& notification = m_notifications[it->second];
  bool actionFound = false;
  for (std::size_t i = 0; i + 1 < notification.actions.size(); i += 2) {
    if (notification.actions[i] == actionKey) {
      actionFound = true;
      break;
    }
  }
  if (!actionFound) {
    return false;
  }

  if (m_actionInvokeCallback) {
    m_actionInvokeCallback(id, actionKey);
  }

  if (closeAfterInvoke) {
    (void)close(id, CloseReason::Dismissed);
  }
  return true;
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
  kLog.debug("notification {} #{}", reason_str, id);
  upsertHistory(closed, false, reason);

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

const std::deque<NotificationHistoryEntry>& NotificationManager::history() const noexcept { return m_history; }

std::uint64_t NotificationManager::changeSerial() const noexcept { return m_changeSerial; }

void NotificationManager::removeHistoryEntry(uint32_t id) {
  const auto it = m_historyIndex.find(id);
  if (it == m_historyIndex.end()) {
    return;
  }

  m_history.erase(m_history.begin() + static_cast<std::ptrdiff_t>(it->second));
  ++m_changeSerial;
  rebuildHistoryIndex();
  schedulePersistHistory();
}

void NotificationManager::clearHistory() {
  if (m_history.empty()) {
    return;
  }

  m_history.clear();
  m_historyIndex.clear();
  ++m_changeSerial;
  markNotificationHistorySeen();
  schedulePersistHistory();
}

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
  int expiryMs = -1;
  const auto now = Clock::now();
  for (const auto& n : m_notifications) {
    if (n.expiryTime) {
      const auto ms = std::chrono::ceil<std::chrono::milliseconds>(*n.expiryTime - now).count();
      const int clamped = static_cast<int>(std::max<long long>(0, ms));
      if (expiryMs < 0 || clamped < expiryMs) {
        expiryMs = clamped;
      }
    }
  }
  return expiryMs;
}

void NotificationManager::processExpired() {
  for (const uint32_t id : expiredIds()) {
    close(id, CloseReason::Expired);
  }
}

void NotificationManager::pauseExpiry(uint32_t id) {
  const auto it = m_idToIndex.find(id);
  if (it == m_idToIndex.end()) {
    return;
  }
  m_notifications[it->second].expiryTime.reset();
  m_notifications[it->second].expiryWallClock.reset();
}

void NotificationManager::resumeExpiry(uint32_t id, int32_t remainingMs) {
  const auto it = m_idToIndex.find(id);
  if (it == m_idToIndex.end()) {
    return;
  }
  if (remainingMs <= 0) {
    m_notifications[it->second].expiryTime = Clock::now();
    m_notifications[it->second].expiryWallClock = WallClock::now();
    return;
  }
  const auto steadyResume = Clock::now();
  const auto wallResume = WallClock::now();
  m_notifications[it->second].expiryTime = steadyResume + std::chrono::milliseconds(remainingMs);
  m_notifications[it->second].expiryWallClock = wallResume + std::chrono::milliseconds(remainingMs);
}

void NotificationManager::setDoNotDisturb(bool enabled) {
  if (m_doNotDisturb == enabled) {
    return;
  }
  m_doNotDisturb = enabled;
  if (m_stateCallback) {
    m_stateCallback();
  }
}

bool NotificationManager::doNotDisturb() const noexcept { return m_doNotDisturb; }

bool NotificationManager::toggleDoNotDisturb() {
  setDoNotDisturb(!m_doNotDisturb);
  return doNotDisturb();
}

void NotificationManager::setStateCallback(StateCallback callback) { m_stateCallback = std::move(callback); }

void NotificationManager::setSoundPlayer(SoundPlayer* soundPlayer) { m_soundPlayer = soundPlayer; }

bool NotificationManager::hasUnreadNotificationHistory() const noexcept { return m_unreadSinceHistoryVisit; }

void NotificationManager::markNotificationHistorySeen() {
  if (!m_unreadSinceHistoryVisit) {
    return;
  }
  m_unreadSinceHistoryVisit = false;
  if (m_stateCallback) {
    m_stateCallback();
  }
}

void NotificationManager::schedulePersistHistory() {
  if (m_persistScheduled) {
    return;
  }
  m_persistScheduled = true;
  DeferredCall::callLater([this]() {
    m_persistScheduled = false;
    persistHistoryToDisk();
  });
}

void NotificationManager::persistHistoryToDisk() {
  const std::string dir = FileUtils::stateDir();
  if (dir.empty()) {
    return;
  }
  std::filesystem::path path(dir);
  std::error_code ec;
  std::filesystem::create_directories(path, ec);
  path /= "notification_history.json";
  (void)saveNotificationHistoryToFile(path, m_history, m_nextId, m_changeSerial);
}

void NotificationManager::loadPersistedHistory() {
  const std::string dir = FileUtils::stateDir();
  if (dir.empty()) {
    return;
  }
  std::filesystem::path path(dir);
  path /= "notification_history.json";
  std::uint32_t nextId = m_nextId;
  std::uint64_t serial = m_changeSerial;
  std::deque<NotificationHistoryEntry> loaded;
  if (!loadNotificationHistoryFromFile(path, loaded, nextId, serial)) {
    return;
  }
  m_history = std::move(loaded);
  m_nextId = nextId;
  m_changeSerial = serial;
  rebuildHistoryIndex();
}

void NotificationManager::flushPersistedHistory() { persistHistoryToDisk(); }
