#include "app/Application.hpp"
#include "core/Log.hpp"

#include <stdexcept>

int main() {
    try {
        logInfo("noctalia hello");
        Application app;
        app.run();
    } catch (const std::exception& e) {
        logError("fatal: {}", e.what());
        return 1;
    }
}
