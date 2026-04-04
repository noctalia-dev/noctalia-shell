#include "Application.h"

#include "app/PollSource.h"
#include "core/Log.h"

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

  m_notificationService.manager().setEventCallback([this](const Notification& n, NotificationEvent event) {
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
  // Explicitly clean up D-Bus services before the bus connection is destroyed
  // This ensures clean disconnection and prevents blocking on shutdown
  if (m_bus != nullptr) {
    // Process any pending D-Bus events to ensure clean state
    m_bus->processPendingEvents();

    // Destroy services in reverse order they were created
    m_trayService.reset();
    m_notificationService.stopDbus();
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
    m_bus = std::make_unique<SessionBus>();
    logInfo("connected to session bus");
  } catch (const std::exception& e) {
    logWarn("dbus disabled: {}", e.what());
    m_notificationService.internal().notify("Noctalia", "Session bus unavailable", e.what(), 8000, Urgency::Low);
  }

  if (m_bus != nullptr) {
    try {
      m_debugService = std::make_unique<DebugService>(*m_bus, m_notificationService.internal());
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
      m_notificationService.internal().notify("Noctalia", "MPRIS disabled", e.what(), 7000, Urgency::Low);
    }

    try {
      m_notificationService.startDbus(*m_bus);
      logInfo("listening on org.freedesktop.Notifications");
    } catch (const std::exception& e) {
      logWarn("notifications disabled: {}", e.what());
      m_notificationService.stopDbus();
      m_notificationService.internal().notify("Noctalia", "DBus notifications disabled", e.what(), 7000, Urgency::Low);
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

  // Initialize bar (top layer)
  m_bar.initialize(m_wayland, &m_configService, &m_timeService, &m_notificationService.manager(), m_trayService.get());

  // Build poll sources
  std::vector<PollSource*> sources;
  if (m_bus != nullptr) {
    m_busPollSource = std::make_unique<SessionBusPollSource>(*m_bus);
    sources.push_back(m_busPollSource.get());
  }
  m_notificationPollSource = std::make_unique<NotificationPollSource>(m_notificationService);
  sources.push_back(m_notificationPollSource.get());
  sources.push_back(&m_timePollSource);
  sources.push_back(&m_configPollSource);
  sources.push_back(&m_statePollSource);

  m_mainLoop = std::make_unique<MainLoop>(m_wayland, m_bar, std::move(sources));
  m_mainLoop->run();

  logInfo("shutdown");
}
