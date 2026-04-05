#pragma once

#include "notification/notification_manager.h"

#include <memory>
#include <sdbus-c++/sdbus-c++.h>
#include <string>

class SessionBus;

class DebugService {
public:
  DebugService(SessionBus& bus, NotificationManager& notifications);

private:
  uint32_t onEmitInternalNotification(const std::string& app_name, const std::string& summary, const std::string& body,
                                      int32_t timeout, uint8_t urgency);
  bool onSetVerboseLogs(bool enabled);
  bool onGetVerboseLogs() const;

  NotificationManager& m_notifications;
  std::unique_ptr<sdbus::IObject> m_object;
  bool m_verbose_logs{false};
};
