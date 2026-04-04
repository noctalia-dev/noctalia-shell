#pragma once

#include "dbus/notification/NotificationService.h"
#include "notification/InternalNotificationService.h"
#include "notification/NotificationManager.h"

#include <memory>

class SessionBus;

class NotificationsService {
public:
  NotificationsService();

  NotificationManager& manager() noexcept { return m_manager; }
  const NotificationManager& manager() const noexcept { return m_manager; }

  InternalNotificationService& internal() noexcept { return m_internal; }
  const InternalNotificationService& internal() const noexcept { return m_internal; }

  void startDbus(SessionBus& bus);
  void stopDbus();
  [[nodiscard]] bool hasDbus() const noexcept { return m_dbus != nullptr; }

  [[nodiscard]] int nextExpiryTimeoutMs() const;
  void processExpiredNotifications();

private:
  NotificationManager m_manager;
  InternalNotificationService m_internal;
  std::unique_ptr<NotificationService> m_dbus;
};
