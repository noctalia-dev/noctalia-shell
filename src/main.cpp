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
#include <fcntl.h>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

namespace {

  enum class SpawnResult { Parent, Child, Error };

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
                "  --help       Show this help message\n"
                "  --version    Show version information\n"
                "  --daemon     Run in background\n"
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

  SpawnResult daemonize(pid_t* out_pid) {
    pid_t pid = ::fork();
    if (pid < 0) {
      std::perror("fork (first)");
      return SpawnResult::Error;
    }

    if (pid > 0) {
      if (out_pid)
        *out_pid = pid;
      return SpawnResult::Parent;
    }

    if (::setsid() < 0) {
      std::perror("setsid");
      _exit(1);
    }

    ::umask(0);
    if (::chdir("/") != 0) {
      std::perror("chdir(\"/\")");
      _exit(1);
    }

    pid = ::fork();
    if (pid < 0) {
      std::perror("fork (second)");
      _exit(1);
    }

    if (pid > 0) {
      _exit(0);
    }

    int fd = ::open("/dev/null", O_RDWR);
    if (fd != -1) {
      ::dup2(fd, STDIN_FILENO);
      ::dup2(fd, STDOUT_FILENO);
      ::dup2(fd, STDERR_FILENO);
      if (fd > STDERR_FILENO)
        ::close(fd);
    }

    return SpawnResult::Child;
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

  bool shouldDaemonize = false;

  for (int i = 1; i < argc; ++i) {
    if (std::strcmp(argv[i], "--daemon") == 0 || std::strcmp(argv[i], "-d") == 0) {
      shouldDaemonize = true;
      for (int j = i; j < argc - 1; ++j) {
        argv[j] = argv[j + 1];
      }
      --argc;
      break;
    }
  }

  if (argc >= 2) {
    if (std::strcmp(argv[1], "theme") == 0)
      return noctalia::theme::runCli(argc, argv);
    if (std::strcmp(argv[1], "msg") == 0)
      return noctalia::ipc::runCli(argc, argv);
    if (std::strcmp(argv[1], "config") == 0)
      return noctalia::config::runCli(argc, argv);
  }

  for (int i = 1; i < argc; ++i) {
    if (argv[i][0] == '-') {
      const int rc = runTopLevelFlag(argv[i]);
      if (rc >= 0)
        return rc;

      std::fprintf(stderr, "error: unknown option: %s\n", argv[i]);
      return 1;
    }
  }

  if (IpcClient::isRunning()) {
    std::fputs("error: noctalia is already running\n", stderr);
    return 1;
  }

  if (shouldDaemonize) {
    pid_t pid = -1;
    SpawnResult result = daemonize(&pid);

    if (result == SpawnResult::Error) {
      return 1;
    }
    if (result == SpawnResult::Parent) {
      std::printf("noctalia started [pid: %d]\n", pid);
      return 0;
    }
  }

  return runShell();
}
