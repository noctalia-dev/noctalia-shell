#pragma once

class Bar;
class NotificationService;

class MainLoop {
public:
    MainLoop(Bar& bar, NotificationService* notifications);

    void run();

private:
    Bar& m_bar;
    NotificationService* m_notifications = nullptr;
};
