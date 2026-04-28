#pragma once

#include "app/main_loop.h"
#include "app/timer_poll_source.h"
#include "config/config_poll_source.h"
#include "config/config_service.h"
#include "core/file_watcher.h"
#include "core/timer_manager.h"
#include "dbus/bluetooth/bluetooth_agent.h"
#include "dbus/bluetooth/bluetooth_service.h"
#include "dbus/mpris/mpris_service.h"
#include "dbus/network/network_secret_agent.h"
#include "dbus/network/network_service.h"
#include "dbus/notification/notification_poll_source.h"
#include "dbus/notification/notification_service.h"
#include "dbus/polkit/polkit_agent.h"
#include "dbus/polkit/polkit_poll_source.h"
#include "dbus/power/power_profiles_service.h"
#include "dbus/session_bus.h"
#include "dbus/session_bus_poll_source.h"
#include "dbus/system_bus.h"
#include "dbus/system_bus_poll_source.h"
#include "dbus/tray/tray_service.h"
#include "dbus/upower/upower_service.h"
#include "debug/debug_service.h"
#include "hooks/hook_manager.h"
#include "idle/idle_inhibitor.h"
#include "idle/idle_manager.h"
#include "ipc/ipc_poll_source.h"
#include "ipc/ipc_service.h"
#include "net/http_client.h"
#include "net/http_client_poll_source.h"
#include "notification/notification_manager.h"
#include "pipewire/pipewire_poll_source.h"
#include "pipewire/pipewire_service.h"
#include "pipewire/pipewire_spectrum.h"
#include "pipewire/pipewire_spectrum_poll_source.h"
#include "pipewire/sound_player.h"
#include "render/core/async_texture_cache.h"
#include "render/core/shared_texture_cache.h"
#include "render/core/thumbnail_service.h"
#include "render/gl_shared_context.h"
#include "render/render_context.h"
#include "shell/bar/bar.h"
#include "shell/desktop/desktop_widgets_controller.h"
#include "shell/desktop/desktop_widgets_poll_source.h"
#include "shell/dock/dock.h"
#include "shell/lockscreen/lock_screen.h"
#include "shell/notification/notification_toast.h"
#include "shell/osd/audio_osd.h"
#include "shell/osd/brightness_osd.h"
#include "shell/osd/osd_overlay.h"
#include "shell/overview/overview.h"
#include "shell/panel/panel_manager.h"
#include "shell/polkit/polkit_panel.h"
#include "shell/session/session_panel.h"
#include "shell/settings/settings_window.h"
#include "shell/tray/tray_menu.h"
#include "shell/wallpaper/wallpaper.h"
#include "system/brightness_poll_source.h"
#include "system/brightness_service.h"
#include "system/desktop_entry_poll_source.h"
#include "system/icon_theme_poll_source.h"
#include "system/night_light_manager.h"
#include "system/system_monitor_service.h"
#include "system/telemetry_service.h"
#include "system/weather_poll_source.h"
#include "system/weather_service.h"
#include "theme/template_apply_service.h"
#include "theme/theme_service.h"
#include "time/time_poll_source.h"
#include "time/time_service.h"
#include "ui/dialogs/color_picker_dialog_popup.h"
#include "ui/dialogs/file_dialog_popup.h"
#include "ui/dialogs/layer_popup_host.h"
#include "wayland/clipboard_poll_source.h"
#include "wayland/clipboard_service.h"
#include "wayland/key_repeat_poll_source.h"
#include "wayland/virtual_keyboard_service.h"
#include "wayland/wayland_connection.h"
#include "wayland/workspace_poll_source.h"

#include <atomic>
#include <memory>
#include <vector>

class Application {
public:
  Application();
  ~Application();

  void run();

  // Public for signal handler
  static std::atomic<bool> s_shutdownRequested;

private:
  void initServices();
  void initUi();
  void initIpc();
  void syncNotificationDaemon();
  void syncPolkitAgent();
  bool runUserCommand(const std::string& command);
  bool runIdleCommand(const std::string& command);
  void onIconThemeChanged();
  void onUpowerStateChangedForHooks();
  void onNetworkStateChangedForHooks(const NetworkState& state);
  void onBluetoothStateChangedForHooks(const BluetoothState& state);
  [[nodiscard]] std::vector<PollSource*> currentPollSources();
  [[nodiscard]] std::vector<PollSource*> buildPollSources();

  WaylandConnection m_wayland;
  ClipboardService m_clipboardService;
  VirtualKeyboardService m_virtualKeyboardService;
  ConfigService m_configService;
  HttpClient m_httpClient;
  noctalia::theme::ThemeService m_themeService{m_configService, m_httpClient};
  noctalia::theme::TemplateApplyService m_templateApplyService{m_configService};
  TimeService m_timeService;
  NotificationManager m_notificationManager;
  std::unique_ptr<SessionBus> m_bus;
  std::unique_ptr<SystemBus> m_systemBus;
  std::unique_ptr<SystemMonitorService> m_systemMonitor;
  std::unique_ptr<DebugService> m_debugService;
  IdleInhibitor m_idleInhibitor;
  IdleManager m_idleManager;
  HookManager m_hookManager;
  NightLightManager m_nightLightManager;
  std::unique_ptr<MprisService> m_mprisService;
  std::unique_ptr<PowerProfilesService> m_powerProfilesService;
  std::unique_ptr<NetworkService> m_networkService;
  std::unique_ptr<NetworkSecretAgent> m_networkSecretAgent;
  std::unique_ptr<BluetoothService> m_bluetoothService;
  std::unique_ptr<BluetoothAgent> m_bluetoothAgent;
  std::unique_ptr<PolkitAgent> m_polkitAgent;
  std::unique_ptr<UPowerService> m_upowerService;
  std::optional<UPowerState> m_prevUpowerForHooks;
  std::optional<bool> m_prevWirelessEnabledForHooks;
  std::optional<bool> m_prevBluetoothPoweredForHooks;
  SessionActionHooks m_sessionActionHooks;
  std::unique_ptr<BrightnessService> m_brightnessService;
  std::unique_ptr<TrayService> m_trayService;
  std::unique_ptr<NotificationService> m_notificationDbus;
  std::unique_ptr<PipeWireService> m_pipewireService;
  std::unique_ptr<PipeWireSpectrum> m_pipewireSpectrum;
  std::unique_ptr<SoundPlayer> m_soundPlayer;

  TelemetryService m_telemetryService;
  FileWatcher m_fileWatcher;

  GlSharedContext m_glShared;
  SharedTextureCache m_sharedTextureCache;
  RenderContext m_renderContext;
  Bar m_bar;
  Dock m_dock;
  DesktopWidgetsController m_desktopWidgetsController;
  LockScreen m_lockScreen;
  PanelManager m_panelManager;
  NotificationToast m_notificationToast;
  AudioOsd m_audioOsd;
  BrightnessOsd m_brightnessOsd;
  OsdOverlay m_osdOverlay;
  TrayMenu m_trayMenu;
  Wallpaper m_wallpaper;
  Overview m_overview;
  SettingsWindow m_settingsWindow;
  LayerPopupHostRegistry m_layerPopupHosts;
  ColorPickerDialogPopup m_colorPickerDialogPopup;
  FileDialogPopup m_fileDialogPopup;
  ThumbnailService m_thumbnailService;
  AsyncTextureCache m_asyncTextureCache;

  // Poll sources (must outlive MainLoop)
  std::unique_ptr<SessionBusPollSource> m_busPollSource;
  std::unique_ptr<SystemBusPollSource> m_systemBusPollSource;
  NotificationPollSource m_notificationPollSource{m_notificationManager};
  TimePollSource m_timePollSource{m_timeService};
  ConfigPollSource m_configPollSource{m_configService};
  DesktopWidgetsPollSource m_desktopWidgetsPollSource{m_desktopWidgetsController};
  DesktopEntryPollSource m_desktopEntryPollSource;
  IconThemePollSource m_iconThemePollSource;
  ClipboardPollSource m_clipboardPollSource{m_clipboardService};
  TimerPollSource m_timerPollSource;
  KeyRepeatPollSource m_keyRepeatPollSource{m_wayland};
  WorkspacePollSource m_workspacePollSource{m_wayland};
  std::unique_ptr<BrightnessPollSource> m_brightnessPollSource;
  std::unique_ptr<PipeWirePollSource> m_pipewirePollSource;
  std::unique_ptr<PipeWireSpectrumPollSource> m_pipewireSpectrumPollSource;
  std::unique_ptr<PolkitPollSource> m_polkitPollSource;
  IpcService m_ipcService;
  IpcPollSource m_ipcPollSource{m_ipcService};
  WeatherService m_weatherService;
  HttpClientPollSource m_httpClientPollSource{m_httpClient};
  FileWatchPollSource m_fileWatchPollSource{m_fileWatcher};
  WeatherPollSource m_weatherPollSource{m_weatherService};
  Timer m_clipboardAutoPasteTimer;

  std::unique_ptr<MainLoop> m_mainLoop;
};
