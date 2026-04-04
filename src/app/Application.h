#pragma once

#include "app/MainLoop.h"
#include "config/ConfigPollSource.h"
#include "config/ConfigService.h"
#include "config/StatePollSource.h"
#include "config/StateService.h"
#include "dbus/SessionBus.h"
#include "dbus/SessionBusPollSource.h"
#include "dbus/SystemBus.h"
#include "dbus/SystemBusPollSource.h"
#include "dbus/mpris/MprisService.h"
#include "dbus/notification/NotificationPollSource.h"
#include "dbus/notification/NotificationService.h"
#include "dbus/power/PowerProfilesService.h"
#include "dbus/tray/TrayService.h"
#include "debug/DebugService.h"
#include "notification/NotificationManager.h"
#include "shell/Bar.h"
#include "shell/Wallpaper.h"
#include "system/SystemMonitorService.h"
#include "time/TimePollSource.h"
#include "time/TimeService.h"
#include "wayland/WaylandConnection.h"

#include <atomic>
#include <memory>

class Application {
public:
  Application();
  ~Application();

  void run();

  // Public for signal handler
  static std::atomic<bool> s_shutdownRequested;

private:
  WaylandConnection m_wayland;
  ConfigService m_configService;
  StateService m_stateService;
  TimeService m_timeService;
  NotificationManager m_notificationManager;
  std::unique_ptr<SessionBus> m_bus;
  std::unique_ptr<SystemBus> m_systemBus;
  std::unique_ptr<SystemMonitorService> m_systemMonitor;
  std::unique_ptr<DebugService> m_debugService;
  std::unique_ptr<MprisService> m_mprisService;
  std::unique_ptr<PowerProfilesService> m_powerProfilesService;
  std::unique_ptr<TrayService> m_trayService;
  std::unique_ptr<NotificationService> m_notificationDbus;

  Bar m_bar;
  Wallpaper m_wallpaper;

  // Poll sources (must outlive MainLoop)
  std::unique_ptr<SessionBusPollSource> m_busPollSource;
  std::unique_ptr<SystemBusPollSource> m_systemBusPollSource;
  NotificationPollSource m_notificationPollSource{m_notificationManager};
  TimePollSource m_timePollSource{m_timeService};
  ConfigPollSource m_configPollSource{m_configService};
  StatePollSource m_statePollSource{m_stateService};

  std::unique_ptr<MainLoop> m_mainLoop;
};
