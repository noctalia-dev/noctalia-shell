#pragma once

class Bar;
class ConfigService;
class NotificationService;
class SessionBus;
class StateService;
class TimeService;
class WaylandConnection;

class MainLoop {
public:
    MainLoop(WaylandConnection& wayland, Bar& bar, SessionBus* bus,
             NotificationService* notifications, TimeService* time,
             ConfigService* config, StateService* state);

    void run();

private:
    WaylandConnection& m_wayland;
    Bar& m_bar;
    SessionBus* m_bus = nullptr;
    NotificationService* m_notifications = nullptr;
    TimeService* m_time = nullptr;
    ConfigService* m_config = nullptr;
    StateService* m_state = nullptr;
};
