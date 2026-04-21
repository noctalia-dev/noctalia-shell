#include "core/process.h"

#include <csignal>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <filesystem>
#include <string_view>
#include <sys/wait.h>
#include <unistd.h>

namespace {

  // Forks, redirects child stdio to /dev/null, and execvp the given args.
  // Returns the child pid in the parent, or -1 on fork failure.
  // Never returns in the child.
  pid_t forkExecDetached(const std::vector<std::string>& args) {
    const pid_t pid = ::fork();
    if (pid != 0) {
      return pid;
    }

    // Child
    ::setsid();

    const int devnull = ::open("/dev/null", O_RDWR);
    if (devnull >= 0) {
      ::dup2(devnull, STDIN_FILENO);
      ::dup2(devnull, STDOUT_FILENO);
      ::dup2(devnull, STDERR_FILENO);
      if (devnull > STDERR_FILENO) {
        ::close(devnull);
      }
    }

    std::vector<char*> argv;
    argv.reserve(args.size() + 1);
    for (const auto& arg : args) {
      argv.push_back(const_cast<char*>(arg.c_str()));
    }
    argv.push_back(nullptr);

    ::execvp(argv[0], argv.data());
    ::_exit(127);
  }

} // namespace

namespace process {

  bool commandExists(const char* name) {
    if (name == nullptr || name[0] == '\0') {
      return false;
    }

    if (std::strchr(name, '/') != nullptr) {
      return ::access(name, X_OK) == 0;
    }

    const char* pathEnv = std::getenv("PATH");
    if (pathEnv == nullptr || pathEnv[0] == '\0') {
      pathEnv = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
    }

    std::string_view path(pathEnv);
    std::size_t start = 0;
    while (start <= path.size()) {
      const std::size_t end = path.find(':', start);
      const std::string_view dir = end == std::string_view::npos ? path.substr(start) : path.substr(start, end - start);
      const std::filesystem::path candidate =
          dir.empty() ? std::filesystem::path(name) : (std::filesystem::path(dir) / name);
      if (::access(candidate.c_str(), X_OK) == 0) {
        return true;
      }
      if (end == std::string_view::npos) {
        break;
      }
      start = end + 1;
    }

    return false;
  }

  bool runAsync(const std::vector<std::string>& args) {
    if (args.empty() || args.front().empty()) {
      return false;
    }
    return forkExecDetached(args) > 0;
  }

  bool runAsync(std::initializer_list<const char*> args) {
    std::vector<std::string> command;
    command.reserve(args.size());
    for (const char* arg : args) {
      if (arg == nullptr) {
        return false;
      }
      command.emplace_back(arg);
    }
    return runAsync(command);
  }

  bool runAsync(const std::string& command) {
    if (command.empty()) {
      return false;
    }
    return runAsync(std::vector<std::string>{"/bin/sh", "-lc", command});
  }

  std::optional<int> launchDetachedTracked(const std::vector<std::string>& args) {
    if (args.empty() || args.front().empty()) {
      return std::nullopt;
    }
    const pid_t pid = forkExecDetached(args);
    if (pid < 0) {
      return std::nullopt;
    }
    return static_cast<int>(pid);
  }

  std::optional<int> launchDetachedTracked(std::initializer_list<const char*> args) {
    std::vector<std::string> command;
    command.reserve(args.size());
    for (const char* arg : args) {
      if (arg == nullptr) {
        return std::nullopt;
      }
      command.emplace_back(arg);
    }
    return launchDetachedTracked(command);
  }

  void terminateTracked(int pid) {
    if (pid <= 0) {
      return;
    }
    const pid_t p = static_cast<pid_t>(pid);
    ::kill(p, SIGTERM);
    int status = 0;
    if (::waitpid(p, &status, WNOHANG) != p) {
      ::kill(p, SIGKILL);
      ::waitpid(p, &status, 0);
    }
  }

  bool runSync(const std::vector<std::string>& args) {
    if (args.empty() || args.front().empty()) {
      return false;
    }

    pid_t pid = fork();
    if (pid < 0) {
      return false;
    }

    if (pid == 0) {
      std::vector<char*> argv;
      argv.reserve(args.size() + 1);
      for (const auto& arg : args) {
        argv.push_back(const_cast<char*>(arg.c_str()));
      }
      argv.push_back(nullptr);

      execvp(argv[0], argv.data());
      _exit(127);
    }

    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
      return false;
    }
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
  }

  bool runSync(const std::string& command) {
    if (command.empty()) {
      return false;
    }
    return runSync(std::vector<std::string>{"/bin/sh", "-lc", command});
  }

  bool launchFirstAvailable(std::initializer_list<std::initializer_list<const char*>> commandVariants) {
    for (const auto& variant : commandVariants) {
      if (variant.size() == 0) {
        continue;
      }
      const char* executable = *variant.begin();
      if (!commandExists(executable)) {
        continue;
      }
      if (runAsync(variant)) {
        return true;
      }
    }
    return false;
  }

} // namespace process
