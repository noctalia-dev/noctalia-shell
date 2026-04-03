#include "Application.hpp"

#include "core/Log.hpp"

#include <csignal>
#include <stdexcept>

std::atomic<bool> Application::s_shutdown_requested{false};

namespace {

void signal_handler(int signum) {
    if (signum == SIGTERM || signum == SIGINT) {
        Application::s_shutdown_requested = true;
    }
}

}  // namespace

Application::Application()
    : m_internalNotifications(m_manager) {
    logInfo("noctalia hello");

    m_manager.setEventCallback([](const Notification& n, NotificationEvent event) {
        const char* kind = (event == NotificationEvent::Added) ? "added" : "updated";
        const char* origin = (n.origin == NotificationOrigin::Internal) ? "internal" : "external";
        logDebug("notification {} id={} origin={}", kind, n.id, origin);
    });
}

void Application::run() {
    // Install signal handlers for graceful shutdown
    std::signal(SIGTERM, signal_handler);
    std::signal(SIGINT, signal_handler);

    m_bar.initialize();

    try {
        m_bus = std::make_unique<SessionBus>();
        logInfo("connected to session bus");
    } catch (const std::exception& e) {
        logWarn("dbus disabled: {}", e.what());
        m_internalNotifications.notify("Noctalia", "Session bus unavailable", e.what(), 8000, Urgency::Low);
    }

    if (m_bus != nullptr) {
        try {
            m_debugService = std::make_unique<DebugService>(*m_bus, m_internalNotifications);
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
            m_internalNotifications.notify("Noctalia", "MPRIS disabled", e.what(), 7000, Urgency::Low);
        }

        try {
            m_notificationService = std::make_unique<NotificationService>(*m_bus, m_manager);
            logInfo("listening on org.freedesktop.Notifications");
        } catch (const std::exception& e) {
            logWarn("notifications disabled: {}", e.what());
            m_notificationService.reset();
            m_internalNotifications.notify("Noctalia", "DBus notifications disabled", e.what(), 7000, Urgency::Low);
        }
    }

    m_mainLoop = std::make_unique<MainLoop>(m_bar, m_bus.get(), m_notificationService.get());
    m_mainLoop->run();

    logInfo("shutdown");
}
