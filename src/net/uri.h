#pragma once

#include <string>
#include <string_view>

namespace uri {

  [[nodiscard]] std::string decodeComponent(std::string_view text);
  [[nodiscard]] bool isRemoteUrl(std::string_view url);
  [[nodiscard]] std::string normalizeFileUrl(std::string_view url);

} // namespace uri
