#include "notification/NotificationsService.h"

#include "dbus/SessionBus.h"

#include <algorithm>

namespace {

int computeExpiryTimeoutMs(const NotificationManager& manager) {
  int expiry_ms = -1;
  const auto now = Clock::now();
  for (const auto& n : manager.all()) {
    if (n.expiry_time) {
      const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(*n.expiry_time - now).count();
      const int clamped = static_cast<int>(std::max<long long>(0, ms));
      if (expiry_ms < 0 || clamped < expiry_ms) {
        expiry_ms = clamped;
      }
    }
  }
  return expiry_ms;
}

} // namespace

NotificationsService::NotificationsService() : m_internal(m_manager) {}

void NotificationsService::startDbus(SessionBus& bus) {
  m_dbus = std::make_unique<NotificationService>(bus, m_manager);
}

void NotificationsService::stopDbus() { m_dbus.reset(); }

int NotificationsService::nextExpiryTimeoutMs() const { return computeExpiryTimeoutMs(m_manager); }

void NotificationsService::processExpiredNotifications() {
  if (m_dbus != nullptr) {
    m_dbus->processExpiredNotifications();
    return;
  }

  for (const uint32_t id : m_manager.expiredIds()) {
    m_manager.close(id, CloseReason::Expired);
  }
}
