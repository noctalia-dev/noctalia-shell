#pragma once

#include "app/PollSource.h"
#include "notification/NotificationManager.h"

class NotificationService;

class NotificationPollSource final : public PollSource {
public:
  explicit NotificationPollSource(NotificationManager& manager) : m_manager(manager) {}

  // Optional: set the D-Bus service for emitting close signals on expiry
  void setDbusService(NotificationService* dbus) { m_dbus = dbus; }

  [[nodiscard]] int pollTimeoutMs() const override { return m_manager.nextExpiryTimeoutMs(); }

  void dispatch(const std::vector<pollfd>& /*fds*/, std::size_t /*startIdx*/) override;

protected:
  void doAddPollFds(std::vector<pollfd>& /*fds*/) override {}

private:
  NotificationManager& m_manager;
  NotificationService* m_dbus = nullptr;
};
