#pragma once

#include "app/MainLoop.hpp"
#include "debug/DebugService.hpp"
#include "dbus/SessionBus.hpp"
#include "dbus/mpris/MprisService.hpp"
#include "dbus/notification/NotificationService.hpp"
#include "notification/InternalNotificationService.hpp"
#include "notification/NotificationManager.hpp"
#include "shell/Bar.hpp"
#include "system/SystemMonitorService.hpp"
#include "time/TimeService.hpp"

#include <atomic>
#include <memory>

class Application {
public:
    Application();

    void run();

    // Public for signal handler
    static std::atomic<bool> s_shutdown_requested;

private:
    TimeService m_timeService;
    Bar m_bar;
    std::unique_ptr<SessionBus> m_bus;
    std::unique_ptr<SystemMonitorService> m_systemMonitor;
    std::unique_ptr<DebugService> m_debugService;
    std::unique_ptr<MprisService> m_mprisService;
    NotificationManager m_manager;
    InternalNotificationService m_internalNotifications;
    std::unique_ptr<NotificationService> m_notificationService;
    std::unique_ptr<MainLoop> m_mainLoop;
};
