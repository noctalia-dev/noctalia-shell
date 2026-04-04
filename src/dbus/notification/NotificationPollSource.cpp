#include "dbus/notification/NotificationPollSource.h"

#include "dbus/notification/NotificationService.h"

void NotificationPollSource::dispatch(const std::vector<pollfd>& /*fds*/, std::size_t /*startIdx*/) {
  if (m_dbus != nullptr) {
    m_dbus->processExpired();
  } else {
    m_manager.processExpired();
  }
}
