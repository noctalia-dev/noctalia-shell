#include "app/application.h"
#include "core/log.h"

#include <stdexcept>

int main() {
  try {
    Application app;
    app.run();
  } catch (const std::exception& e) {
    logError("fatal: {}", e.what());
    return 1;
  }
}
