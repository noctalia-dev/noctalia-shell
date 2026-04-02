#include "Application.hpp"

#include <iostream>

Application::Application()
    : m_service(m_manager)
{
    m_manager.setEventCallback([](const Notification& n, NotificationEvent event) {
        const char* kind = (event == NotificationEvent::Added) ? "added" : "updated";
        std::cout << "[noctalia] event " << kind << " id=" << n.id << '\n';
    });
}

void Application::run() {
    std::cout << "noctalia: listening on org.freedesktop.Notifications\n";
    m_service.run();
}
