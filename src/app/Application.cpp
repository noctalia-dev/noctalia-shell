#include "Application.h"

#include "app/PollSource.h"
#include "core/Log.h"
#include "shell/panels/TestPanelContent.h"

#include <csignal>
#include <stdexcept>

std::atomic<bool> Application::s_shutdownRequested{false};

namespace {

void signal_handler(int signum) {
  if (signum == SIGTERM || signum == SIGINT) {
    Application::s_shutdownRequested = true;
  }
}

} // namespace

Application::Application() {
  logInfo("noctalia hello");

  m_notificationManager.addEventCallback([this](const Notification& n, NotificationEvent event) {
    const char* kind = "updated";
    if (event == NotificationEvent::Added) {
      kind = "added";
    } else if (event == NotificationEvent::Closed) {
      kind = "closed";
    }
    const char* origin = (n.origin == NotificationOrigin::Internal) ? "internal" : "external";
    logDebug("notification {} id={} origin={}", kind, n.id, origin);

    // Keep bar widgets in sync with notification state changes.
    m_bar.onWorkspaceChange();
  });
}

Application::~Application() {
  if (m_systemBus != nullptr) {
    m_systemBus->processPendingEvents();
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

  // MainLoop will be destroyed next, then SessionBus
}

void Application::run() {
  // Install signal handlers for graceful shutdown
  std::signal(SIGTERM, signal_handler);
  std::signal(SIGINT, signal_handler);

  // Connect to Wayland
  if (!m_wayland.connect()) {
    throw std::runtime_error("failed to connect to Wayland display");
  }

  // Set up output/workspace change callbacks
  m_wayland.setOutputChangeCallback([this]() {
    m_wallpaper.onOutputChange();
    m_bar.onOutputChange();
  });

  m_wayland.setWorkspaceChangeCallback([this]() { m_bar.onWorkspaceChange(); });

  // Initialize wallpaper first (background layer)
  m_wallpaper.initialize(m_wayland, &m_configService, &m_stateService);

  try {
    m_systemMonitor = std::make_unique<SystemMonitorService>();
    if (m_systemMonitor->isRunning()) {
      logInfo("system monitor service active");
    }
  } catch (const std::exception& e) {
    logWarn("system monitor service disabled: {}", e.what());
    m_systemMonitor.reset();
  }

  try {
    m_systemBus = std::make_unique<SystemBus>();
    logInfo("connected to system bus");
  } catch (const std::exception& e) {
    logWarn("system dbus disabled: {}", e.what());
    m_systemBus.reset();
  }

  if (m_systemBus != nullptr) {
    try {
      m_powerProfilesService = std::make_unique<PowerProfilesService>(*m_systemBus);
      m_powerProfilesService->setChangeCallback(
          [this](const PowerProfilesState& /*state*/) { m_bar.onWorkspaceChange(); });
      if (!m_powerProfilesService->activeProfile().empty()) {
        logInfo("power profiles active profile: {}", m_powerProfilesService->activeProfile());
      } else {
        logInfo("power profiles service active");
      }
    } catch (const std::exception& e) {
      logWarn("power profiles disabled: {}", e.what());
      m_powerProfilesService.reset();
    }
  }

  try {
    m_bus = std::make_unique<SessionBus>();
    logInfo("connected to session bus");
  } catch (const std::exception& e) {
    logWarn("dbus disabled: {}", e.what());
    m_notificationManager.addInternal("Noctalia", "Session bus unavailable", e.what(), 8000, Urgency::Low);
  }

  if (m_bus != nullptr) {
    try {
      m_debugService = std::make_unique<DebugService>(*m_bus, m_notificationManager);
      logInfo("debug service active on dev.noctalia.Debug");
    } catch (const std::exception& e) {
      logWarn("debug service disabled: {}", e.what());
      m_debugService.reset();
    }

    try {
      m_mprisService = std::make_unique<MprisService>(*m_bus);
      logInfo("mpris discovery active");
    } catch (const std::exception& e) {
      logWarn("mpris disabled: {}", e.what());
      m_mprisService.reset();
      m_notificationManager.addInternal("Noctalia", "MPRIS disabled", e.what(), 7000, Urgency::Low);
    }

    try {
      m_notificationDbus = std::make_unique<NotificationService>(*m_bus, m_notificationManager);
      m_notificationPollSource.setDbusService(m_notificationDbus.get());
      logInfo("listening on org.freedesktop.Notifications");
    } catch (const std::exception& e) {
      logWarn("notifications disabled: {}", e.what());
      m_notificationDbus.reset();
      m_notificationManager.addInternal("Noctalia", "DBus notifications disabled", e.what(), 7000, Urgency::Low);
    }

    try {
      m_trayService = std::make_unique<TrayService>(*m_bus);
      m_trayService->setChangeCallback([this]() { m_bar.onWorkspaceChange(); });
      logInfo("status notifier watcher active on org.kde.StatusNotifierWatcher");
    } catch (const std::exception& e) {
      logWarn("tray watcher disabled: {}", e.what());
      m_trayService.reset();
    }
  }

  // Initialize the shared render context (EGL, shaders, fonts — created once)
  m_renderContext.initialize(m_wayland.display());

  // Initialize panel manager (must be before bar so widgets can access PanelManager::instance())
  m_panelManager.initialize(m_wayland, &m_configService, &m_renderContext);
  m_panelManager.registerPanel("test", std::make_unique<TestPanelContent>());

  // Initialize notification popup (top layer, dynamic surface)
  m_notificationPopup.initialize(m_wayland, &m_configService, &m_notificationManager, &m_renderContext);

  // Initialize bar (top layer)
  m_bar.initialize(m_wayland, &m_configService, &m_timeService, &m_notificationManager, m_trayService.get(),
                   &m_renderContext);

  // Unified pointer event routing — both Bar and PanelManager check surface ownership
  m_wayland.setPointerEventCallback([this](const PointerEvent& event) {
    m_bar.onPointerEvent(event);
    m_panelManager.onPointerEvent(event);
    m_notificationPopup.onPointerEvent(event);
  });

  // Build poll sources
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

  m_mainLoop = std::make_unique<MainLoop>(m_wayland, m_bar, std::move(sources));
  m_mainLoop->run();

  logInfo("shutdown");
}
