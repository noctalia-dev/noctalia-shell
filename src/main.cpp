#include "notification/NotificationManager.hpp"
#include "dbus/NotificationService.hpp"

#include <iostream>
#include <stdexcept>

int main() {
    try {
        NotificationManager manager;
        manager.setEventCallback([](const Notification& n, NotificationEvent event) {
            const char* kind = (event == NotificationEvent::Added) ? "added" : "updated";
            std::cout << "[noctalia] event " << kind << " id=" << n.id << '\n';
        });

        NotificationService service(manager);

        std::cout << "noctalia: listening on org.freedesktop.Notifications\n";
        service.run();
    } catch (const std::exception& e) {
        std::cerr << "fatal: " << e.what() << '\n';
        return 1;
    }
}
