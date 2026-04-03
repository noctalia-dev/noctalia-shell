#pragma once

class Application;
class Bar;
class ConfigService;
class NotificationService;
class SessionBus;
class TimeService;

class MainLoop {
public:
    MainLoop(Bar& bar, SessionBus* bus, NotificationService* notifications,
             TimeService* time, ConfigService* config);

    void run();

private:
    Bar& m_bar;
    SessionBus* m_bus = nullptr;
    NotificationService* m_notifications = nullptr;
    TimeService* m_time = nullptr;
    ConfigService* m_config = nullptr;
};
