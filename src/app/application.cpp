#include "application.h"

#include "app/poll_source.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "core/process.h"
#include "i18n/i18n_service.h"
#include "launcher/app_provider.h"
#include "launcher/emoji_provider.h"
#include "launcher/math_provider.h"
#include "shell/clipboard/clipboard_panel.h"
#include "shell/clipboard/clipboard_paste.h"
#include "shell/control_center/control_center_panel.h"
#include "shell/launcher/launcher_panel.h"
#include "shell/session/session_panel.h"
#include "shell/test/test_panel.h"
#include "shell/wallpaper/panel/wallpaper_panel.h"
#include "system/distro_info.h"
#include "ui/controls/input.h"
#include "ui/style.h"

#include <chrono>
#include <cmath>
#include <csignal>
#include <cstdlib>
#include <stdexcept>
#include <thread>

std::atomic<bool> Application::s_shutdownRequested{false};

namespace {

  constexpr Logger kLog("app");

  bool launchLogoutCommand() {
    const char* sessionId = std::getenv("XDG_SESSION_ID");
    if (sessionId != nullptr && sessionId[0] != '\0') {
      return process::launchDetached({"loginctl", "terminate-session", sessionId});
    }

    const char* user = std::getenv("USER");
    if (user != nullptr && user[0] != '\0') {
      return process::launchDetached({"loginctl", "terminate-user", user});
    }

    return false;
  }

  template <typename Factory>
  auto makeWithStartupBackoff(std::string_view label, Factory&& factory) -> decltype(factory()) {
    using namespace std::chrono_literals;

    constexpr int kAttempts = 7;
    auto delay = 50ms;
    int failedAttempts = 0;

    for (int attempt = 1; attempt <= kAttempts; ++attempt) {
      try {
        auto value = factory();
        if (failedAttempts > 0) {
          kLog.info("{} init succeeded after {} retr{}", label, failedAttempts, failedAttempts == 1 ? "y" : "ies");
        }
        return value;
      } catch (const std::exception& e) {
        if (attempt == kAttempts) {
          throw;
        }

        failedAttempts = attempt;
        kLog.warn("{} init attempt {}/{} failed: {}; retrying in {}ms", label, attempt, kAttempts, e.what(),
                  delay.count());
        std::this_thread::sleep_for(delay);
        delay *= 2;
      }
    }

    throw std::runtime_error(std::string(label) + " init failed");
  }

  void signal_handler(int signum) {
    if (signum == SIGTERM || signum == SIGINT) {
      Application::s_shutdownRequested = true;
    }
  }

} // namespace

Application::Application() : m_weatherService(m_configService, m_httpClient) {
  m_notificationManager.addEventCallback([this](const Notification& n, NotificationEvent event) {
    const char* kind = "updated";
    if (event == NotificationEvent::Added) {
      kind = "added";
    } else if (event == NotificationEvent::Closed) {
      kind = "closed";
    }
    const char* origin = (n.origin == NotificationOrigin::Internal) ? "internal" : "external";
    kLog.debug("notification {} id={} origin={}", kind, n.id, origin);

    // Keep bar widgets in sync with notification state changes.
    m_bar.refresh();
    m_panelManager.refresh();
  });
}

Application::~Application() {
  m_wayland.setClipboardService(nullptr);
  m_wayland.setVirtualKeyboardService(nullptr);

  if (m_systemBus != nullptr) {
    m_systemBus->processPendingEvents();
    m_upowerService.reset();
    m_powerProfilesService.reset();
    m_systemBus->processPendingEvents();
  }

  // Explicitly clean up D-Bus services before the bus connection is destroyed
  // This ensures clean disconnection and prevents blocking on shutdown
  if (m_bus != nullptr) {
    // Process any pending D-Bus events to ensure clean state
    m_bus->processPendingEvents();

    // Destroy services in reverse order they were created
    m_trayService.reset();
    m_notificationDbus.reset();
    m_mprisService.reset();
    m_debugService.reset();

    // Process any final cleanup events
    m_bus->processPendingEvents();
  }

  // PipeWire cleanup
  m_pipewireSpectrumPollSource.reset();
  m_pipewireSpectrum.reset();
  m_pipewirePollSource.reset();
  m_pipewireService.reset();

  // MainLoop will be destroyed next, then SessionBus
}

void Application::syncNotificationDaemon() {
  if (m_bus == nullptr) {
    m_notificationDbus.reset();
    m_notificationPollSource.setDbusService(nullptr);
    return;
  }

  if (!m_configService.config().shell.notificationsDbus) {
    if (m_notificationDbus != nullptr) {
      kLog.info("notification daemon disabled by config");
    }
    m_notificationDbus.reset();
    m_notificationPollSource.setDbusService(nullptr);
    return;
  }

  if (m_notificationDbus != nullptr) {
    return;
  }

  try {
    m_notificationDbus = makeWithStartupBackoff("notification service", [this]() {
      return std::make_unique<NotificationService>(*m_bus, m_notificationManager);
    });
    m_notificationPollSource.setDbusService(m_notificationDbus.get());
    kLog.info("listening on org.freedesktop.Notifications");
  } catch (const std::exception& e) {
    kLog.warn("notifications disabled: {}", e.what());
    m_notificationDbus.reset();
    m_notificationPollSource.setDbusService(nullptr);
    m_notificationManager.addInternal("Noctalia", "DBus notifications disabled", e.what(), Urgency::Low);
  }
}

void Application::run() {
  initLogFile();
  kLog.info("noctalia v{}", NOCTALIA_VERSION);
  initServices();
  initUi();
  initIpc();
  m_mainLoop = std::make_unique<MainLoop>(m_wayland, m_bar, buildPollSources());
  m_mainLoop->run();
  kLog.info("shutdown");
}

void Application::initServices() {
  std::signal(SIGTERM, signal_handler);
  std::signal(SIGINT, signal_handler);

  // i18n has no dependencies on other services and must be ready before any
  // UI construction reads a translated string.
  i18n::Service::instance().init(m_configService.config().shell.lang);
  m_configService.addReloadCallback(
      [this]() { i18n::Service::instance().setLanguage(m_configService.config().shell.lang); });

  // Apply theme before any UI constructs palette-dependent scene nodes.
  m_themeService.apply();
  m_configService.addReloadCallback([this]() { m_themeService.onConfigReload(); });

  if (!m_wayland.connect()) {
    throw std::runtime_error("failed to connect to Wayland display");
  }
  m_wayland.setClipboardService(&m_clipboardService);
  m_wayland.setVirtualKeyboardService(&m_virtualKeyboardService);
  Input::setClipboardService(&m_clipboardService);

  m_wayland.setOutputChangeCallback([this]() {
    m_wallpaper.onOutputChange();
    m_overview.onOutputChange();
    m_bar.onOutputChange();
    m_lockScreen.onOutputChange();
  });
  m_clipboardService.setChangeCallback([this]() {
    if (m_panelManager.isOpen() && m_panelManager.activePanelId() == "clipboard") {
      m_panelManager.refresh();
    }
  });
  m_wayland.setWorkspaceChangeCallback([this]() { m_bar.refresh(); });
  m_wayland.setToplevelChangeCallback([this]() { m_bar.refresh(); });

  m_idleInhibitor.initialize(m_wayland, &m_renderContext);
  m_idleInhibitor.setChangeCallback([this]() { m_bar.refresh(); });
  m_idleManager.initialize(m_wayland);
  m_idleManager.setCommandRunner([this](const std::string& command) { return runIdleCommand(command); });
  m_idleManager.reload(m_configService.config().idle);
  m_configService.addReloadCallback([this]() { m_idleManager.reload(m_configService.config().idle); });
  m_nightLightManager.reload(m_configService.config().nightlight);
  m_nightLightManager.setChangeCallback([this]() { m_bar.refresh(); });
  m_configService.addReloadCallback([this]() { m_nightLightManager.reload(m_configService.config().nightlight); });

  m_wallpaper.initialize(m_wayland, &m_configService, &m_stateService);
  m_overview.initialize(m_wayland, &m_configService, &m_stateService, &m_wallpaper);

  // Override the single-callback slot set by Wallpaper::initialize() so both
  // wallpaper and overview are notified of wallpaper path changes.
  m_stateService.setWallpaperChangeCallback([this]() {
    m_wallpaper.onStateChange();
    m_overview.onStateChange();
    m_themeService.onWallpaperChange();
  });

  m_themeService.setChangeCallback([this]() {
    m_bar.reload();
    m_panelManager.close();
  });

  if (const auto distro = DistroDetector::detect(); distro.has_value()) {
    const auto& label = !distro->prettyName.empty() ? distro->prettyName
                        : !distro->name.empty()     ? distro->name
                                                    : distro->id;
    kLog.info("distro: {}", label);
  } else {
    kLog.info("distro: unknown");
  }

  try {
    m_systemMonitor = std::make_unique<SystemMonitorService>();
    if (m_systemMonitor->isRunning()) {
      kLog.info("system monitor service active");
    }
  } catch (const std::exception& e) {
    kLog.warn("system monitor service disabled: {}", e.what());
    m_systemMonitor.reset();
  }

  try {
    m_systemBus = makeWithStartupBackoff("system dbus", []() { return std::make_unique<SystemBus>(); });
    kLog.info("connected to system bus");
  } catch (const std::exception& e) {
    kLog.warn("system dbus disabled: {}", e.what());
    m_systemBus.reset();
  }

  if (m_systemBus != nullptr) {
    try {
      m_powerProfilesService = std::make_unique<PowerProfilesService>(*m_systemBus);
      m_powerProfilesService->setChangeCallback([this](const PowerProfilesState& /*state*/) { m_bar.refresh(); });
      if (!m_powerProfilesService->activeProfile().empty()) {
        kLog.info("power profiles active profile: {}", m_powerProfilesService->activeProfile());
      } else {
        kLog.info("power profiles service active");
      }
    } catch (const std::exception& e) {
      kLog.warn("power profiles disabled: {}", e.what());
      m_powerProfilesService.reset();
    }

    try {
      m_upowerService = std::make_unique<UPowerService>(*m_systemBus);
      m_upowerService->setChangeCallback([this]() { m_bar.refresh(); });
    } catch (const std::exception& e) {
      kLog.warn("upower disabled: {}", e.what());
      m_upowerService.reset();
    }
  }

  try {
    m_pipewireService = std::make_unique<PipeWireService>();
    m_pipewireSpectrum = std::make_unique<PipeWireSpectrum>(*m_pipewireService);
  } catch (const std::exception& e) {
    kLog.warn("pipewire disabled: {}", e.what());
    m_pipewireSpectrum.reset();
    m_pipewireService.reset();
  }

  try {
    m_bus = makeWithStartupBackoff("session dbus", []() { return std::make_unique<SessionBus>(); });
    kLog.info("connected to session bus");
  } catch (const std::exception& e) {
    kLog.warn("dbus disabled: {}", e.what());
    m_notificationManager.addInternal("Noctalia", "Session bus unavailable", e.what(), Urgency::Low);
  }

  if (m_bus != nullptr) {
    try {
      m_debugService = makeWithStartupBackoff(
          "debug service", [this]() { return std::make_unique<DebugService>(*m_bus, m_notificationManager); });
      kLog.info("debug service active on dev.noctalia.Debug");
    } catch (const std::exception& e) {
      kLog.warn("debug service disabled: {}", e.what());
      m_debugService.reset();
    }

    try {
      m_mprisService =
          makeWithStartupBackoff("mpris service", [this]() { return std::make_unique<MprisService>(*m_bus); });
      m_mprisService->setChangeCallback([this]() {
        m_bar.refresh();
        m_panelManager.refresh();
      });
      kLog.info("mpris discovery active");
    } catch (const std::exception& e) {
      kLog.warn("mpris disabled: {}", e.what());
      m_mprisService.reset();
      m_notificationManager.addInternal("Noctalia", "MPRIS disabled", e.what(), Urgency::Low);
    }

    syncNotificationDaemon();
    m_configService.addReloadCallback([this]() { syncNotificationDaemon(); });

    try {
      m_trayService =
          makeWithStartupBackoff("tray service", [this]() { return std::make_unique<TrayService>(*m_bus); });
      m_trayService->setChangeCallback([this]() {
        m_bar.refresh();
        m_trayMenu.onTrayChanged();
      });
      m_trayService->setMenuToggleCallback([this](const std::string& itemId) { m_trayMenu.toggleForItem(itemId); });
    } catch (const std::exception& e) {
      kLog.warn("tray watcher disabled: {}", e.what());
      m_trayService.reset();
    }
  }

  m_weatherService.initialize();
  if (m_weatherService.hasData()) {
    const WeatherSnapshot& snapshot = m_weatherService.snapshot();
    m_nightLightManager.setWeatherCoordinates(snapshot.latitude, snapshot.longitude);
  } else {
    m_nightLightManager.setWeatherCoordinates(std::nullopt, std::nullopt);
  }
  m_weatherService.addChangeCallback([this]() {
    if (m_weatherService.hasData()) {
      const WeatherSnapshot& snapshot = m_weatherService.snapshot();
      m_nightLightManager.setWeatherCoordinates(snapshot.latitude, snapshot.longitude);
    } else {
      m_nightLightManager.setWeatherCoordinates(std::nullopt, std::nullopt);
    }
    m_bar.refresh();
    m_panelManager.refresh();
  });
}

void Application::initUi() {
  m_renderContext.initialize(m_wayland.display());
  m_lockScreen.initialize(m_wayland, &m_renderContext, &m_stateService);

  // Panel manager must be before bar so widgets can access PanelManager::instance()
  m_panelManager.initialize(m_wayland, &m_configService, &m_renderContext);
  auto clipboardPanel = std::make_unique<ClipboardPanel>(&m_clipboardService);
  clipboardPanel->setActivateCallback([this](const ClipboardEntry& entry) {
    m_panelManager.close();
    const ClipboardAutoPasteMode mode = m_configService.config().shell.clipboardAutoPaste;
    if (mode == ClipboardAutoPasteMode::Off) {
      return;
    }
    const ClipboardEntry selectedEntry = entry;
    m_clipboardAutoPasteTimer.stop();
    m_clipboardAutoPasteTimer.start(std::chrono::milliseconds(Style::animFast + 30), [this, selectedEntry]() {
      DeferredCall::callLater([this, selectedEntry]() {
        const ClipboardAutoPasteMode activeMode = m_configService.config().shell.clipboardAutoPaste;
        (void)clipboard_paste::pasteEntry(selectedEntry, activeMode, m_virtualKeyboardService);
      });
    });
  });
  m_panelManager.registerPanel("clipboard", std::move(clipboardPanel));
  m_panelManager.registerPanel(
      "session", std::make_unique<SessionPanel>(SessionPanel::Actions{
                     .logout =
                         [this]() {
                           if (!launchLogoutCommand()) {
                             m_notificationManager.addInternal("Noctalia", "Logout unavailable",
                                                               "Could not determine how to terminate this session.");
                           }
                         },
                     .reboot =
                         [this]() {
                           if (!process::launchFirstAvailable({{"systemctl", "reboot"}, {"loginctl", "reboot"}})) {
                             m_notificationManager.addInternal("Noctalia", "Reboot failed",
                                                               "Could not launch systemctl reboot.");
                           }
                         },
                     .shutdown =
                         [this]() {
                           if (!process::launchFirstAvailable({{"systemctl", "poweroff"}, {"loginctl", "poweroff"}})) {
                             m_notificationManager.addInternal("Noctalia", "Shutdown failed",
                                                               "Could not launch a shutdown command.");
                           }
                         },
                     .lock =
                         [this]() {
                           if (!m_lockScreen.lock()) {
                             m_notificationManager.addInternal("Noctalia", "Lock unavailable",
                                                               "The session lock protocol is not available.");
                           }
                         },
                 }));
  m_panelManager.registerPanel("test", std::make_unique<TestPanel>());
  m_panelManager.registerPanel(
      "control-center",
      std::make_unique<ControlCenterPanel>(&m_notificationManager, m_pipewireService.get(), m_mprisService.get(),
                                           &m_configService, &m_httpClient, &m_weatherService, m_pipewireSpectrum.get(),
                                           m_upowerService.get(), m_powerProfilesService.get()));
  {
    auto launcherPanel = std::make_unique<LauncherPanel>();
    launcherPanel->addProvider(std::make_unique<AppProvider>(&m_wayland));
    launcherPanel->addProvider(std::make_unique<MathProvider>(&m_clipboardService));
    launcherPanel->addProvider(std::make_unique<EmojiProvider>(&m_clipboardService));
    m_panelManager.registerPanel("launcher", std::move(launcherPanel));
  }
  m_panelManager.registerPanel("wallpaper", std::make_unique<WallpaperPanel>(&m_wayland, &m_configService,
                                                                             &m_stateService, &m_thumbnailService));

  m_notificationToast.initialize(m_wayland, &m_configService, &m_notificationManager, &m_renderContext);
  m_configService.setNotificationManager(&m_notificationManager);

  m_osdOverlay.initialize(m_wayland, &m_configService, &m_renderContext);
  m_audioOsd.bindOverlay(m_osdOverlay);
  if (m_pipewireService != nullptr) {
    m_audioOsd.primeFromService(*m_pipewireService);
  }

  m_trayMenu.initialize(m_wayland, &m_configService, m_trayService.get(), &m_renderContext);

  m_bar.initialize(m_wayland, &m_configService, &m_timeService, &m_notificationManager, m_trayService.get(),
                   m_pipewireService.get(), m_upowerService.get(), m_systemMonitor.get(), m_powerProfilesService.get(),
                   &m_idleInhibitor, m_mprisService.get(), &m_httpClient, &m_weatherService, &m_renderContext,
                   &m_nightLightManager);

  m_timeService.setTickSecondCallback([this]() {
    if (m_lockScreen.isActive()) {
      if (m_timeService.format("{:%S}") == "00") {
        m_lockScreen.onSecondTick();
      }
    } else {
      m_bar.onSecondTick();
    }
  });

  if (m_pipewireService != nullptr) {
    m_audioOsd.suppressFor(std::chrono::milliseconds(2000));
    m_pipewireService->setChangeCallback([this]() {
      if (m_pipewireSpectrum != nullptr) {
        m_pipewireSpectrum->handleAudioStateChanged();
      }
      m_bar.refresh();
      m_panelManager.refresh();
      if (m_pipewireService != nullptr) {
        m_audioOsd.onAudioStateChanged(*m_pipewireService);
      }
    });
    m_pipewireService->setVolumePreviewCallback([this](bool isInput, std::uint32_t id, float volume, bool muted) {
      if (isInput) {
        m_audioOsd.showInput(id, volume, muted);
      } else {
        m_audioOsd.showOutput(id, volume, muted);
      }
    });
  }

  if (m_pipewireSpectrum != nullptr) {
    m_pipewireSpectrum->setChangeCallback([this]() {
      if (m_panelManager.isOpen() && m_panelManager.activePanelId() == "control-center") {
        m_panelManager.refresh();
      }
    });
  }

  m_wayland.setPointerEventCallback([this](const PointerEvent& event) {
    if (m_lockScreen.isActive()) {
      m_lockScreen.onPointerEvent(event);
      return;
    }
    if (m_trayMenu.onPointerEvent(event))
      return;
    if (m_bar.onPointerEvent(event))
      return;
    if (m_panelManager.onPointerEvent(event))
      return;
    m_notificationToast.onPointerEvent(event);
  });

  m_wayland.setKeyboardEventCallback([this](const KeyboardEvent& event) {
    if (m_lockScreen.isActive()) {
      m_lockScreen.onKeyboardEvent(event);
      return;
    }
    m_panelManager.onKeyboardEvent(event);
  });
}

void Application::initIpc() {
  if (m_ipcService.start()) {
    kLog.info("IPC socket at {}", m_ipcService.socketPath());
  } else {
    kLog.warn("IPC disabled: could not bind socket");
  }

  m_ipcService.registerHandler(
      "status",
      [this](const std::string&) -> std::string {
        const bool panelOpen = m_panelManager.isOpen();
        std::string json = "{\n";
        json += "  \"barVisible\": ";
        json += m_bar.isVisible() ? "true" : "false";
        json += ",\n  \"panelOpen\": ";
        json += panelOpen ? "true" : "false";
        json += ",\n  \"activePanelId\": ";
        json += panelOpen ? ("\"" + m_panelManager.activePanelId() + "\"") : "null";
        json += "\n}\n";
        return json;
      },
      "status", "Print current state as JSON");

  m_ipcService.registerHandler(
      "reload-config",
      [this](const std::string&) -> std::string {
        m_configService.forceReload();
        return "ok\n";
      },
      "reload-config", "Reload the config file");

  m_ipcService.registerHandler(
      "show-bar",
      [this](const std::string&) -> std::string {
        m_bar.show();
        return "ok\n";
      },
      "show-bar", "Show the bar");

  m_ipcService.registerHandler(
      "hide-bar",
      [this](const std::string&) -> std::string {
        m_bar.hide();
        return "ok\n";
      },
      "hide-bar", "Hide the bar");

  m_ipcService.registerHandler(
      "toggle-bar",
      [this](const std::string&) -> std::string {
        m_bar.isVisible() ? m_bar.hide() : m_bar.show();
        return "ok\n";
      },
      "toggle-bar", "Toggle bar visibility");

  m_ipcService.registerHandler(
      "lock",
      [this](const std::string&) -> std::string {
        if (m_lockScreen.lock()) {
          return "ok\n";
        }
        return "error: lock screen unavailable\n";
      },
      "lock", "Lock the session using the development lock screen (press Escape to unlock)");

  m_ipcService.registerHandler(
      "toggle-panel",
      [this](const std::string& args) -> std::string {
        if (args.empty()) {
          return "error: toggle-panel requires a panel id\n";
        }
        m_panelManager.togglePanel(args);
        return "ok\n";
      },
      "toggle-panel <id>", "Toggle a panel by id (e.g. control-center)");

  m_ipcService.registerHandler(
      "enable-idle-inhibitor",
      [this](const std::string&) -> std::string {
        if (!m_idleInhibitor.available()) {
          return "error: idle inhibitor protocol unavailable\n";
        }
        m_idleInhibitor.setEnabled(true);
        return "ok\n";
      },
      "enable-idle-inhibitor", "Enable the compositor idle inhibitor");

  m_ipcService.registerHandler(
      "disable-idle-inhibitor",
      [this](const std::string&) -> std::string {
        if (!m_idleInhibitor.available()) {
          return "error: idle inhibitor protocol unavailable\n";
        }
        m_idleInhibitor.setEnabled(false);
        return "ok\n";
      },
      "disable-idle-inhibitor", "Disable the compositor idle inhibitor");

  m_ipcService.registerHandler(
      "toggle-idle-inhibitor",
      [this](const std::string&) -> std::string {
        if (!m_idleInhibitor.available()) {
          return "error: idle inhibitor protocol unavailable\n";
        }
        m_idleInhibitor.toggle();
        return "ok\n";
      },
      "toggle-idle-inhibitor", "Toggle the compositor idle inhibitor");

  m_ipcService.registerHandler(
      "enable-nightlight",
      [this](const std::string&) -> std::string {
        m_nightLightManager.setEnabled(true);
        return "ok\n";
      },
      "enable-nightlight", "Enable night light schedule");

  m_ipcService.registerHandler(
      "disable-nightlight",
      [this](const std::string&) -> std::string {
        m_nightLightManager.setEnabled(false);
        return "ok\n";
      },
      "disable-nightlight", "Disable night light schedule");

  m_ipcService.registerHandler(
      "toggle-nightlight",
      [this](const std::string&) -> std::string {
        m_nightLightManager.toggleEnabled();
        return "ok\n";
      },
      "toggle-nightlight", "Toggle night light schedule");

  m_ipcService.registerHandler(
      "toggle-force-nightlight",
      [this](const std::string&) -> std::string {
        m_nightLightManager.toggleForceEnabled();
        return "ok\n";
      },
      "toggle-force-nightlight", "Toggle forced night light mode");
}

bool Application::runIdleCommand(const std::string& command) {
  constexpr std::string_view prefix = "noctalia:";

  if (command.rfind(prefix, 0) == 0) {
    const std::string response = m_ipcService.execute(command.substr(prefix.size()));
    if (response.rfind("error:", 0) == 0) {
      kLog.warn("idle IPC command '{}' failed: {}", command, response.substr(0, response.find('\n')));
      return false;
    }
    return true;
  }

  if (!process::launchShellCommand(command)) {
    kLog.warn("idle command failed to launch: {}", command);
    return false;
  }
  return true;
}

std::vector<PollSource*> Application::buildPollSources() {
  std::vector<PollSource*> sources;
  if (m_bus != nullptr) {
    m_busPollSource = std::make_unique<SessionBusPollSource>(*m_bus);
    sources.push_back(m_busPollSource.get());
  }
  if (m_systemBus != nullptr) {
    m_systemBusPollSource = std::make_unique<SystemBusPollSource>(*m_systemBus);
    sources.push_back(m_systemBusPollSource.get());
  }
  sources.push_back(&m_notificationPollSource);
  sources.push_back(&m_timePollSource);
  sources.push_back(&m_configPollSource);
  sources.push_back(&m_statePollSource);
  sources.push_back(&m_desktopEntryPollSource);
  sources.push_back(&m_clipboardPollSource);
  sources.push_back(&m_timerPollSource);
  sources.push_back(&m_keyRepeatPollSource);
  sources.push_back(&m_workspacePollSource);
  if (m_pipewireService != nullptr) {
    m_pipewirePollSource = std::make_unique<PipeWirePollSource>(*m_pipewireService);
    sources.push_back(m_pipewirePollSource.get());
  }
  if (m_pipewireSpectrum != nullptr) {
    m_pipewireSpectrumPollSource = std::make_unique<PipeWireSpectrumPollSource>(*m_pipewireSpectrum);
    sources.push_back(m_pipewireSpectrumPollSource.get());
  }
  sources.push_back(&m_ipcPollSource);
  sources.push_back(&m_httpClientPollSource);
  sources.push_back(&m_weatherPollSource);
  sources.push_back(&m_thumbnailService);
  return sources;
}
