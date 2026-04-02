#include "Application.hpp"

#include <iostream>
#include <stdexcept>

Application::Application() {
    m_manager.setEventCallback([](const Notification& n, NotificationEvent event) {
        const char* kind = (event == NotificationEvent::Added) ? "added" : "updated";
        std::cout << "[noctalia] event " << kind << " id=" << n.id << '\n';
    });
}

void Application::run() {
    m_shell.initialize();

    try {
        m_notificationService = std::make_unique<NotificationService>(m_manager);
        std::cout << "noctalia: listening on org.freedesktop.Notifications\n";
    } catch (const std::exception& e) {
        std::cout << "noctalia: notifications disabled: " << e.what() << '\n';
        m_notificationService.reset();
    }

    m_mainLoop = std::make_unique<MainLoop>(m_shell, m_notificationService.get());
    m_mainLoop->run();
}
