#pragma once

class Application;
class Bar;
class NotificationService;
class SessionBus;

class MainLoop {
public:
    MainLoop(Bar& bar, SessionBus* bus, NotificationService* notifications);

    void run();

private:
    Bar& m_bar;
    SessionBus* m_bus = nullptr;
    NotificationService* m_notifications = nullptr;
};
