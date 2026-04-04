#pragma once

#include "app/PollSource.h"
#include "dbus/notification/NotificationService.h"

class NotificationPollSource final : public PollSource {
public:
  explicit NotificationPollSource(NotificationService& notifications) : m_notifications(notifications) {}

  [[nodiscard]] int pollTimeoutMs() const override { return m_notifications.nextExpiryTimeoutMs(); }

  void dispatch(const std::vector<pollfd>& /*fds*/, std::size_t /*startIdx*/) override {
    m_notifications.processExpiredNotifications();
  }

protected:
  void doAddPollFds(std::vector<pollfd>& /*fds*/) override {}

private:
  NotificationService& m_notifications;
};
