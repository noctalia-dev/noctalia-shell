#pragma once

class BarShell;
class NotificationService;

class MainLoop {
public:
    MainLoop(BarShell& shell, NotificationService* notifications);

    void run();

private:
    BarShell& m_shell;
    NotificationService* m_notifications = nullptr;
};
