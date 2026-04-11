#pragma once

#include <initializer_list>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace process {

  [[nodiscard]] bool commandExists(const char* name);
  [[nodiscard]] bool launchDetached(const std::vector<std::string>& args);
  [[nodiscard]] bool launchDetached(std::initializer_list<const char*> args);
  [[nodiscard]] std::optional<int> launchDetachedTracked(const std::vector<std::string>& args);
  [[nodiscard]] std::optional<int> launchDetachedTracked(std::initializer_list<const char*> args);
  void terminateTracked(int pid);
  [[nodiscard]] bool runSync(const std::vector<std::string>& args);
  [[nodiscard]] bool launchShellCommand(const std::string& command);
  [[nodiscard]] bool launchFirstAvailable(std::initializer_list<std::initializer_list<const char*>> commandVariants);

} // namespace process
