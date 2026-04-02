#include "notification/NotificationManager.hpp"
#include "dbus/NotificationService.hpp"

#include <iostream>
#include <stdexcept>

int main() {
    try {
        NotificationManager manager;
        NotificationService service(manager);

        std::cout << "noctalia: listening on org.freedesktop.Notifications\n";
        service.run();
    } catch (const std::exception& e) {
        std::cerr << "fatal: " << e.what() << '\n';
        return 1;
    }
}
