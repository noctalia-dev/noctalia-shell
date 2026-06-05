#pragma once

#include <filesystem>
#include <functional>
#include <string>
#include <string_view>
#include <unordered_set>
#include <vector>

struct MprisPlayerInfo;
class HttpClient;

namespace mpris {

  [[nodiscard]] bool isRemoteArtUrl(std::string_view url);
  [[nodiscard]] std::string effectiveArtUrl(const MprisPlayerInfo& player);
  // Ordered download URLs for an effective art URL: the primary plus any lower-res
  // fallback (e.g. i.ytimg maxresdefault → hqdefault) tried when the primary 404s.
  [[nodiscard]] std::vector<std::string> artFetchCandidates(std::string_view primaryUrl);

  // Local file to decode for artUrl right now: the file path for file URLs, or the
  // cached download for remote URLs. Empty when a remote URL isn't cached yet. Never
  // starts a download.
  [[nodiscard]] std::string cachedArtworkPath(std::string_view artUrl);
  // Like cachedArtworkPath, but for an uncached remote URL kicks off a deduped
  // background download (see artFetchCandidates) keyed in `pending`; `onReady` runs
  // when a download lands. Returns empty until the file exists.
  [[nodiscard]] std::string resolveArtworkSource(
      HttpClient* httpClient, std::unordered_set<std::string>& pending, std::string_view artUrl,
      std::function<void()> onReady
  );
  [[nodiscard]] std::string normalizeArtPath(std::string_view artUrl);
  [[nodiscard]] std::filesystem::path artCachePath(std::string_view artUrl);
  [[nodiscard]] std::string joinArtists(const std::vector<std::string>& artists);

} // namespace mpris
