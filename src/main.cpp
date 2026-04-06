#include "app/application.h"
#include "core/log.h"

#include <cstring>
#include <stdexcept>

#ifndef NOCTALIA_VERSION
#define NOCTALIA_VERSION "unknown"
#endif

int main(int argc, char* argv[]) {
  for (int i = 1; i < argc; ++i) {
    if (std::strcmp(argv[i], "--version") == 0) {
      std::puts("noctalia " NOCTALIA_VERSION);
      return 0;
    }
    if (std::strcmp(argv[i], "--help") == 0) {
      std::puts("Usage: noctalia [OPTIONS]\n"
                "\n"
                "Options:\n"
                "  --help     Show this help message\n"
                "  --version  Show version information");
      return 0;
    }
  }

  try {
    Application app;
    app.run();
  } catch (const std::exception& e) {
    logError("fatal: {}", e.what());
    return 1;
  }
}
