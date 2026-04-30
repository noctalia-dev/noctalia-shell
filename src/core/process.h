#pragma once

#include <initializer_list>
#include <optional>
#include <string>
#include <vector>

namespace process {

  struct RunResult {
    int exitCode = -1;
    std::string out;
    std::string err;

    operator bool() const { return exitCode == 0; }
  };

  [[nodiscard]] bool commandExists(const char* name);

  // Shell string — runs via /bin/sh -lc
  [[nodiscard]] bool runAsync(const std::string& command);
  [[nodiscard]] RunResult runSync(const std::string& command);

  // Arg vector — direct execvp
  [[nodiscard]] bool runAsync(const std::vector<std::string>& args);
  [[nodiscard]] bool runAsync(std::initializer_list<const char*> args);
  [[nodiscard]] RunResult runSync(const std::vector<std::string>& args);
  [[nodiscard]] RunResult runSync(std::initializer_list<const char*> args);

  [[nodiscard]] std::optional<int> launchDetachedTracked(const std::vector<std::string>& args);
  [[nodiscard]] std::optional<int> launchDetachedTracked(std::initializer_list<const char*> args);
  void terminateTracked(int pid);

  [[nodiscard]] bool launchFirstAvailable(std::initializer_list<std::initializer_list<const char*>> commandVariants);

} // namespace process
