#pragma once

#include <cstdlib>
#include <string_view>

namespace SysUtils {

  [[nodiscard]] inline bool isEnvFlagOn(const char* name) {
    const char* s = std::getenv(name);
    if (s == nullptr) {
      return false;
    }
    std::string_view sv(s);
    return !sv.empty() && sv != "0" && sv != "false" && sv != "no" && sv != "off";
  }

} // namespace SysUtils
