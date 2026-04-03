#include "Application.hpp"

#include "core/Log.hpp"

#include <stdexcept>

Application::Application() {
    m_manager.setEventCallback([](const Notification& n, NotificationEvent event) {
        const char* kind = (event == NotificationEvent::Added) ? "added" : "updated";
        logDebug("notification {} id={}", kind, n.id);
    });
}

void Application::run() {
    m_shell.initialize();

    try {
        m_notificationService = std::make_unique<NotificationService>(m_manager);
        logInfo("listening on org.freedesktop.Notifications");
    } catch (const std::exception& e) {
        logWarn("notifications disabled: {}", e.what());
        m_notificationService.reset();
    }

    m_mainLoop = std::make_unique<MainLoop>(m_shell, m_notificationService.get());
    m_mainLoop->run();
}
