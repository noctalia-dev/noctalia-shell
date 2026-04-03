#pragma once

#include "app/MainLoop.hpp"
#include "dbus/SessionBus.hpp"
#include "dbus/notification/NotificationService.hpp"
#include "notification/NotificationManager.hpp"
#include "shell/Bar.hpp"

#include <memory>

class Application {
public:
    Application();

    void run();

private:
    Bar m_bar;
    std::unique_ptr<SessionBus> m_bus;
    NotificationManager m_manager;
    std::unique_ptr<NotificationService> m_notificationService;
    std::unique_ptr<MainLoop> m_mainLoop;
};
