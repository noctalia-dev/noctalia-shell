#pragma once

#include "app/MainLoop.hpp"
#include "dbus/notification/NotificationService.hpp"
#include "notification/NotificationManager.hpp"
#include "shell/BarShell.hpp"

#include <memory>

class Application {
public:
    Application();

    void run();

private:
    BarShell m_shell;
    NotificationManager m_manager;
    std::unique_ptr<NotificationService> m_notificationService;
    std::unique_ptr<MainLoop> m_mainLoop;
};
