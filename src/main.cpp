#include "app/Application.hpp"

#include <iostream>
#include <stdexcept>

int main() {
    try {
        Application app;
        app.run();
    } catch (const std::exception& e) {
        std::cerr << "fatal: " << e.what() << '\n';
        return 1;
    }
}
