#pragma once

#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

struct MprisPlayerInfo;

namespace mpris {

  [[nodiscard]] bool isRemoteArtUrl(std::string_view url);
  [[nodiscard]] std::string effectiveArtUrl(const MprisPlayerInfo& player);
  [[nodiscard]] std::string normalizeArtPath(std::string_view artUrl);
  [[nodiscard]] std::filesystem::path artCachePath(std::string_view artUrl);
  [[nodiscard]] std::string joinArtists(const std::vector<std::string>& artists);

} // namespace mpris
