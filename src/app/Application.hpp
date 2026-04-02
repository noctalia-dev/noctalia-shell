#pragma once

#include "dbus/notification/NotificationService.hpp"
#include "notification/NotificationManager.hpp"

class Application {
public:
    Application();

    void run();

private:
    NotificationManager m_manager;
    NotificationService m_service;
};
