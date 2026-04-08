#include "app/application.h"
#include "core/log.h"
#include "ipc/ipc_client.h"

#include <cstring>
#include <stdexcept>
#include <string>

int main(int argc, char* argv[]) {
  if (argc >= 2 && std::strcmp(argv[1], "msg") == 0) {
    // noctalia msg <command> [args...]
    if (argc < 3) {
      std::fputs("error: msg requires a command (try: noctalia msg --help)\n", stderr);
      return 1;
    }
    std::string cmd = argv[2];
    for (int i = 3; i < argc; ++i) {
      cmd += ' ';
      cmd += argv[i];
    }
    return IpcClient::send(cmd);
  }

  for (int i = 1; i < argc; ++i) {
    if (std::strcmp(argv[i], "--version") == 0) {
      std::puts("noctalia v" NOCTALIA_VERSION);
      return 0;
    }
    if (std::strcmp(argv[i], "--help") == 0) {
      std::puts("Usage: noctalia [OPTIONS]\n"
                "\n"
                "Options:\n"
                "  --help     Show this help message\n"
                "  --version  Show version information\n"
                "\n"
                "Subcommands:\n"
                "  msg <command>  Send a command to the running instance\n"
                "                 Run 'noctalia msg --help' for available commands\n"
                "\n"
                "For more information and documentation, visit:\n"
                "  https://noctalia.dev");
      return 0;
    }
  }

  if (IpcClient::isRunning()) {
    std::fputs("error: noctalia is already running\n", stderr);
    return 1;
  }

  try {
    Application app;
    app.run();
  } catch (const std::exception& e) {
    logError("fatal: {}", e.what());
    return 1;
  }
}
