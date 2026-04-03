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

Application::Application() {
    logInfo("noctalia hello");

    m_manager.setEventCallback([](const Notification& n, NotificationEvent event) {
        const char* kind = (event == NotificationEvent::Added) ? "added" : "updated";
        logDebug("notification {} id={}", kind, n.id);
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
    }

    if (m_bus != nullptr) {
        try {
            m_notificationService = std::make_unique<NotificationService>(*m_bus, m_manager);
            logInfo("listening on org.freedesktop.Notifications");
        } catch (const std::exception& e) {
            logWarn("notifications disabled: {}", e.what());
            m_notificationService.reset();
        }
    }

    m_mainLoop = std::make_unique<MainLoop>(m_bar, m_bus.get(), m_notificationService.get());
    m_mainLoop->run();

    logInfo("shutdown");
}
