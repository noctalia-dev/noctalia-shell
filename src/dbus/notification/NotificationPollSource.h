#pragma once

#include "app/PollSource.h"
#include "notification/NotificationsService.h"

class NotificationPollSource final : public PollSource {
public:
  explicit NotificationPollSource(NotificationsService& notifications) : m_notifications(notifications) {}

  [[nodiscard]] int pollTimeoutMs() const override { return m_notifications.nextExpiryTimeoutMs(); }

  void dispatch(const std::vector<pollfd>& /*fds*/, std::size_t /*startIdx*/) override {
    m_notifications.processExpiredNotifications();
  }

protected:
  void doAddPollFds(std::vector<pollfd>& /*fds*/) override {}

private:
  NotificationsService& m_notifications;
};
