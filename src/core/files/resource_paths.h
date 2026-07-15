#pragma once

#include <filesystem>
#include <string_view>

namespace paths {

  [[nodiscard]] const std::filesystem::path& assetsRoot();
  [[nodiscard]] std::filesystem::path assetPath(std::string_view relativePath);

} // namespace paths
