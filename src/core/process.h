#pragma once

#include <initializer_list>
#include <string>
#include <string_view>
#include <vector>

namespace process {

  [[nodiscard]] bool commandExists(const char* name);
  [[nodiscard]] bool launchDetached(const std::vector<std::string>& args);
  [[nodiscard]] bool launchDetached(std::initializer_list<const char*> args);
  [[nodiscard]] bool runSync(const std::vector<std::string>& args);
  [[nodiscard]] bool launchShellCommand(const std::string& command);
  [[nodiscard]] bool launchFirstAvailable(std::initializer_list<std::initializer_list<const char*>> commandVariants);

} // namespace process
