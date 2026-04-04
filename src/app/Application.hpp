#pragma once

#include "app/MainLoop.hpp"
#include "config/ConfigPollSource.hpp"
#include "config/ConfigService.hpp"
#include "config/StatePollSource.hpp"
#include "config/StateService.hpp"
#include "dbus/SessionBus.hpp"
#include "dbus/SessionBusPollSource.hpp"
#include "dbus/mpris/MprisService.hpp"
#include "dbus/notification/NotificationPollSource.hpp"
#include "dbus/notification/NotificationService.hpp"
#include "debug/DebugService.hpp"
#include "notification/InternalNotificationService.hpp"
#include "notification/NotificationManager.hpp"
#include "shell/Bar.hpp"
#include "shell/Wallpaper.hpp"
#include "system/SystemMonitorService.hpp"
#include "time/TimePollSource.hpp"
#include "time/TimeService.hpp"
#include "wayland/WaylandConnection.hpp"

#include <atomic>
#include <memory>

class Application {
public:
    Application();
    ~Application();

    void run();

    // Public for signal handler
    static std::atomic<bool> s_shutdown_requested;

private:
    WaylandConnection m_wayland;
    ConfigService m_configService;
    StateService m_stateService;
    TimeService m_timeService;
    Bar m_bar;
    Wallpaper m_wallpaper;
    std::unique_ptr<SessionBus> m_bus;
    std::unique_ptr<SystemMonitorService> m_systemMonitor;
    std::unique_ptr<DebugService> m_debugService;
    std::unique_ptr<MprisService> m_mprisService;
    NotificationManager m_manager;
    InternalNotificationService m_internalNotifications;
    std::unique_ptr<NotificationService> m_notificationService;

    // Poll sources (must outlive MainLoop)
    std::unique_ptr<SessionBusPollSource> m_busPollSource;
    std::unique_ptr<NotificationPollSource> m_notificationPollSource;
    TimePollSource m_timePollSource{m_timeService};
    ConfigPollSource m_configPollSource{m_configService};
    StatePollSource m_statePollSource{m_stateService};

    std::unique_ptr<MainLoop> m_mainLoop;
};
