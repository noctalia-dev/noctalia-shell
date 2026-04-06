#pragma once

#include "app/main_loop.h"
#include "config/config_poll_source.h"
#include "config/config_service.h"
#include "config/state_poll_source.h"
#include "config/state_service.h"
#include "dbus/mpris/mpris_service.h"
#include "dbus/notification/notification_poll_source.h"
#include "dbus/notification/notification_service.h"
#include "dbus/power/power_profiles_service.h"
#include "dbus/session_bus.h"
#include "dbus/session_bus_poll_source.h"
#include "dbus/system_bus.h"
#include "dbus/system_bus_poll_source.h"
#include "dbus/tray/tray_service.h"
#include "dbus/upower/upower_service.h"
#include "debug/debug_service.h"
#include "notification/notification_manager.h"
#include "pipewire/pipewire_poll_source.h"
#include "pipewire/pipewire_service.h"
#include "render/render_context.h"
#include "shell/bar/bar.h"
#include "shell/notification/notification_popup.h"
#include "shell/osd/audio_osd.h"
#include "shell/osd/osd_overlay.h"
#include "shell/panel/panel_manager.h"
#include "shell/tray/tray_menu.h"
#include "shell/wallpaper/wallpaper.h"
#include "system/system_monitor_service.h"
#include "time/time_poll_source.h"
#include "time/time_service.h"
#include "wayland/key_repeat_poll_source.h"
#include "wayland/wayland_connection.h"

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
  std::unique_ptr<UPowerService> m_upowerService;
  std::unique_ptr<TrayService> m_trayService;
  std::unique_ptr<NotificationService> m_notificationDbus;
  std::unique_ptr<PipeWireService> m_pipewireService;

  RenderContext m_renderContext;
  Bar m_bar;
  PanelManager m_panelManager;
  NotificationPopup m_notificationPopup;
  AudioOsd m_audioOsd;
  OsdOverlay m_osdOverlay;
  TrayMenu m_trayMenu;
  Wallpaper m_wallpaper;

  // Poll sources (must outlive MainLoop)
  std::unique_ptr<SessionBusPollSource> m_busPollSource;
  std::unique_ptr<SystemBusPollSource> m_systemBusPollSource;
  NotificationPollSource m_notificationPollSource{m_notificationManager};
  TimePollSource m_timePollSource{m_timeService};
  ConfigPollSource m_configPollSource{m_configService};
  StatePollSource m_statePollSource{m_stateService};
  KeyRepeatPollSource m_keyRepeatPollSource{m_wayland};
  std::unique_ptr<PipeWirePollSource> m_pipewirePollSource;

  std::unique_ptr<MainLoop> m_mainLoop;
};
