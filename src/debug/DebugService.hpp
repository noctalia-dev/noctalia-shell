#pragma once

#include "notification/InternalNotificationService.hpp"

#include <memory>
#include <sdbus-c++/sdbus-c++.h>
#include <string>

class SessionBus;

class DebugService {
public:
    DebugService(SessionBus& bus, InternalNotificationService& internal_notifications);

private:
    uint32_t onEmitInternalNotification(const std::string& app_name,
                                        const std::string& summary,
                                        const std::string& body,
                                        int32_t timeout,
                                        uint8_t urgency);
    bool onSetVerboseLogs(bool enabled);
    bool onGetVerboseLogs() const;

    InternalNotificationService& m_internal_notifications;
    std::unique_ptr<sdbus::IObject> m_object;
    bool m_verbose_logs{false};
};
