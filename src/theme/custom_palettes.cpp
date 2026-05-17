#include "theme/custom_palettes.h"

#include "util/file_utils.h"

#include <algorithm>
#include <filesystem>
#include <string>
#include <system_error>

namespace noctalia::theme {

  std::filesystem::path customPaletteDir() {
    const std::string dir = FileUtils::configDir();
    return dir.empty() ? std::filesystem::path{} : std::filesystem::path(dir) / "palettes";
  }

  std::filesystem::path customPalettePath(std::string_view name) {
    return customPaletteDir() / (std::string(name) + ".json");
  }

  std::vector<AvailablePalette> availableCustomPalettes() {
    const auto dir = customPaletteDir();
    if (dir.empty()) {
      return {};
    }
    std::error_code ec;
    if (!std::filesystem::is_directory(dir, ec) || ec) {
      return {};
    }
    std::vector<AvailablePalette> out;
    for (const auto& entry : std::filesystem::directory_iterator(dir, ec)) {
      if (ec || !entry.is_regular_file(ec) || ec) {
        continue;
      }
      const auto& path = entry.path();
      if (path.extension() != ".json") {
        continue;
      }
      out.push_back(AvailablePalette{path.stem().string()});
    }
    std::sort(out.begin(), out.end(),
              [](const AvailablePalette& a, const AvailablePalette& b) { return a.name < b.name; });
    return out;
  }

} // namespace noctalia::theme
