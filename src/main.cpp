#include "app/application.h"
#include "config/cli.h"
#include "core/build_info.h"
#include "core/log.h"
#include "ipc/cli.h"
#include "ipc/ipc_client.h"
#include "theme/cli.h"

#include <clocale>
#include <cstdio>
#include <cstring>
#include <stdexcept>
#include <string>

namespace {

  int runTopLevelFlag(const char* flag) {
    if (std::strcmp(flag, "--version") == 0) {
      const std::string version = noctalia::build_info::displayVersion();
      std::printf("noctalia %s\n", version.c_str());
      return 0;
    }
    if (std::strcmp(flag, "--help") == 0) {
      std::puts("Usage: noctalia [OPTIONS]\n"
                "\n"
                "Options:\n"
                "  --help     Show this help message\n"
                "  --version  Show version information\n"
                "\n"
                "Subcommands:\n"
                "  msg <command>    Send a command to the running instance\n"
                "                   Run 'noctalia msg --help' for available commands\n"
                "  theme <image>    Generate a color palette from an image\n"
                "                   Run 'noctalia theme --help' for options\n"
                "  config <command> Config support and replay helpers\n"
                "                   Run 'noctalia config --help' for options\n"
                "\n"
                "For more information and documentation, visit:\n"
                "  https://noctalia.dev");
      return 0;
    }
    return -1;
  }

  int runShell() {
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
    return 0;
  }

} // namespace

int main(int argc, char* argv[]) {
  std::setlocale(LC_ALL, "");
  if (argc >= 2) {
    if (std::strcmp(argv[1], "theme") == 0)
      return noctalia::theme::runCli(argc, argv);
    if (std::strcmp(argv[1], "msg") == 0)
      return noctalia::ipc::runCli(argc, argv);
    if (std::strcmp(argv[1], "config") == 0)
      return noctalia::config::runCli(argc, argv);
  }

  for (int i = 1; i < argc; ++i) {
    const int rc = runTopLevelFlag(argv[i]);
    if (rc >= 0)
      return rc;
  }

  return runShell();
}
