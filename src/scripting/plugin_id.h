#pragma once

#include <cctype>
#include <optional>
#include <string>
#include <string_view>

namespace scripting {

  [[nodiscard]] inline bool isValidPluginIdSegment(std::string_view segment) {
    if (segment.empty()) {
      return false;
    }
    const auto first = static_cast<unsigned char>(segment.front());
    if (std::isalnum(first) == 0) {
      return false;
    }
    for (const char ch : segment) {
      const auto c = static_cast<unsigned char>(ch);
      if (std::isalnum(c) != 0 || ch == '_' || ch == '-' || ch == '.') {
        continue;
      }
      return false;
    }
    return segment != "." && segment != "..";
  }

  [[nodiscard]] inline bool isValidPluginId(std::string_view id) {
    const std::size_t slash = id.find('/');
    if (slash == std::string_view::npos || id.find('/', slash + 1) != std::string_view::npos) {
      return false;
    }
    return isValidPluginIdSegment(id.substr(0, slash)) && isValidPluginIdSegment(id.substr(slash + 1));
  }

  // Repo subdir for a plugin id by convention: "author/foo" lives at "foo/".
  [[nodiscard]] inline std::optional<std::string> pluginSubdirFromId(std::string_view id) {
    if (!isValidPluginId(id)) {
      return std::nullopt;
    }
    return std::string(id.substr(id.find('/') + 1));
  }

} // namespace scripting
