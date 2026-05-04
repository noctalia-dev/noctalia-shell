#include "dbus/mpris/mpris_service.h"

#include "core/deferred_call.h"
#include "core/log.h"
#include "core/timer_manager.h"
#include "dbus/session_bus.h"
#include "ipc/ipc_arg_parse.h"
#include "ipc/ipc_service.h"
#include "util/string_utils.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <format>
#include <limits>
#include <map>
#include <sdbus-c++/IObject.h>
#include <sdbus-c++/IProxy.h>
#include <sdbus-c++/Types.h>
#include <string_view>
#include <tuple>
#include <unordered_set>

std::string joinedArtists(const std::vector<std::string>& artists) {
  if (artists.empty()) {
    return {};
  }
  std::string joined = artists.front();
  for (std::size_t i = 1; i < artists.size(); ++i) {
    joined += ", ";
    joined += artists[i];
  }
  return joined;
}

namespace {

  static constexpr auto k_dbus_interface = "org.freedesktop.DBus";
  static constexpr auto k_properties_interface = "org.freedesktop.DBus.Properties";
  static constexpr auto k_mpris_root_interface = "org.mpris.MediaPlayer2";
  static constexpr auto k_mpris_player_interface = "org.mpris.MediaPlayer2.Player";
  static constexpr auto k_noctalia_mpris_interface = "dev.noctalia.Mpris";
  static constexpr auto k_properties_debounce_window = std::chrono::milliseconds{120};
  static constexpr auto k_metadata_stabilize_window = std::chrono::milliseconds{900};
  static const sdbus::ServiceName k_dbus_name{"org.freedesktop.DBus"};
  static const sdbus::ObjectPath k_dbus_path{"/org/freedesktop/DBus"};
  static const sdbus::ObjectPath k_mpris_path{"/org/mpris/MediaPlayer2"};
  static const sdbus::ServiceName k_noctalia_mpris_bus_name{"dev.noctalia.Mpris"};
  static const sdbus::ObjectPath k_noctalia_mpris_object_path{"/dev/noctalia/Mpris"};

  bool is_mpris_bus_name(std::string_view name) { return name.starts_with("org.mpris.MediaPlayer2."); }

  bool is_valid_loop_status(std::string_view loop_status) {
    return loop_status == "None" || loop_status == "Track" || loop_status == "Playlist";
  }

  template <typename T>
  T get_property_or(sdbus::IProxy& proxy, std::string_view interface_name, std::string_view property_name, T fallback) {
    try {
      const sdbus::Variant value = proxy.getProperty(property_name).onInterface(interface_name);
      return value.get<T>();
    } catch (const sdbus::Error&) {
      return fallback;
    }
  }

  std::map<std::string, sdbus::Variant> get_metadata_or(sdbus::IProxy& proxy) {
    return get_property_or(proxy, k_mpris_player_interface, "Metadata", std::map<std::string, sdbus::Variant>{});
  }

  std::string get_string_from_variant(const std::map<std::string, sdbus::Variant>& values, std::string_view key) {
    const auto it = values.find(std::string{key});
    if (it == values.end()) {
      return {};
    }

    try {
      return it->second.get<std::string>();
    } catch (const sdbus::Error&) {
      return {};
    }
  }

  std::string get_object_path_from_variant(const std::map<std::string, sdbus::Variant>& values, std::string_view key) {
    const auto it = values.find(std::string{key});
    if (it == values.end()) {
      return {};
    }

    try {
      return it->second.get<sdbus::ObjectPath>();
    } catch (const sdbus::Error&) {
      try {
        return it->second.get<std::string>();
      } catch (const sdbus::Error&) {
        return {};
      }
    }
  }

  std::vector<std::string> get_string_array_from_variant(const std::map<std::string, sdbus::Variant>& values,
                                                         std::string_view key) {
    const auto it = values.find(std::string{key});
    if (it == values.end()) {
      return {};
    }

    try {
      return it->second.get<std::vector<std::string>>();
    } catch (const sdbus::Error&) {
      return {};
    }
  }

  int64_t get_int64_from_variant(const std::map<std::string, sdbus::Variant>& values, std::string_view key) {
    const auto it = values.find(std::string{key});
    if (it == values.end()) {
      return 0;
    }

    try {
      return it->second.get<int64_t>();
    } catch (const sdbus::Error&) {
      try {
        const auto value = it->second.get<uint64_t>();
        return value > static_cast<uint64_t>(std::numeric_limits<int64_t>::max()) ? std::numeric_limits<int64_t>::max()
                                                                                  : static_cast<int64_t>(value);
      } catch (const sdbus::Error&) {
        try {
          return static_cast<int64_t>(it->second.get<int32_t>());
        } catch (const sdbus::Error&) {
          try {
            return static_cast<int64_t>(it->second.get<uint32_t>());
          } catch (const sdbus::Error&) {
            return 0;
          }
        }
      }
    }
  }

  std::string get_string_from_props(const std::map<std::string, sdbus::Variant>& props, const char* key) {
    auto it = props.find(key);
    if (it == props.end()) {
      return {};
    }
    try {
      return it->second.get<std::string>();
    } catch (const sdbus::Error&) {
      return {};
    }
  }

  std::string get_string_from_props_or(const std::map<std::string, sdbus::Variant>& props, const char* key,
                                       const char* fallback) {
    auto it = props.find(key);
    if (it == props.end()) {
      return fallback;
    }
    try {
      return it->second.get<std::string>();
    } catch (const sdbus::Error&) {
      return fallback;
    }
  }

  bool get_bool_from_props(const std::map<std::string, sdbus::Variant>& props, const char* key) {
    auto it = props.find(key);
    if (it == props.end()) {
      return false;
    }
    try {
      return it->second.get<bool>();
    } catch (const sdbus::Error&) {
      return false;
    }
  }

  double get_double_from_props(const std::map<std::string, sdbus::Variant>& props, const char* key, double fallback) {
    auto it = props.find(key);
    if (it == props.end()) {
      return fallback;
    }
    try {
      return it->second.get<double>();
    } catch (const sdbus::Error&) {
      return fallback;
    }
  }

  std::map<std::string, sdbus::Variant> get_variant_map_from_props(const std::map<std::string, sdbus::Variant>& props,
                                                                   const char* key) {
    auto it = props.find(key);
    if (it == props.end()) {
      return {};
    }
    try {
      return it->second.get<std::map<std::string, sdbus::Variant>>();
    } catch (const sdbus::Error&) {
      return {};
    }
  }

  [[maybe_unused]] std::string primary_artist(const std::vector<std::string>& artists) {
    if (artists.empty()) {
      return {};
    }
    return artists.front();
  }

  [[maybe_unused]] std::string joinKeys(const std::map<std::string, sdbus::Variant>& values) {
    std::string out;
    bool first = true;
    for (const auto& [key, _] : values) {
      if (!first) {
        out += ", ";
      }
      first = false;
      out += key;
    }
    return out;
  }

  [[maybe_unused]] std::string joinStrings(const std::vector<std::string>& values) {
    std::string out;
    bool first = true;
    for (const auto& value : values) {
      if (!first) {
        out += ", ";
      }
      first = false;
      out += value;
    }
    return out;
  }

  bool hasStrongNowPlayingMetadata(const MprisPlayerInfo& info) {
    // Track IDs/source URLs can exist during transient "loading" states where the
    // user-visible metadata is still placeholder-only (e.g. app identity + logo).
    // Treat metadata as strong only when actual now-playing fields are present.
    return !info.title.empty() || !info.artists.empty() || !info.album.empty();
  }

  std::string canonicalTrackSourceUrl(std::string_view rawUrl) {
    if (rawUrl.empty()) {
      return {};
    }

    std::string url(rawUrl);
    const auto fragmentPos = url.find('#');
    if (fragmentPos != std::string::npos) {
      url.resize(fragmentPos);
    }

    const auto queryPos = url.find('?');
    if (queryPos == std::string::npos) {
      return url;
    }

    const std::string base = url.substr(0, queryPos);
    const std::string query = url.substr(queryPos + 1);
    std::vector<std::string> keptParams;
    std::size_t start = 0;
    while (start <= query.size()) {
      const auto end = query.find('&', start);
      const std::string_view param = end == std::string::npos ? std::string_view(query).substr(start)
                                                              : std::string_view(query).substr(start, end - start);
      if (!param.empty()) {
        const auto equalsPos = param.find('=');
        const std::string_view key = equalsPos == std::string::npos ? param : param.substr(0, equalsPos);
        if (key != "t" && key != "start" && key != "time_continue") {
          keptParams.emplace_back(param);
        }
      }
      if (end == std::string::npos) {
        break;
      }
      start = end + 1;
    }

    if (keptParams.empty()) {
      return base;
    }

    std::string normalized = base + "?";
    for (std::size_t i = 0; i < keptParams.size(); ++i) {
      if (i > 0) {
        normalized += '&';
      }
      normalized += keptParams[i];
    }
    return normalized;
  }

  std::string logicalTrackSignature(const MprisPlayerInfo& info) {
    const std::string canonicalSourceUrl = canonicalTrackSourceUrl(info.sourceUrl);
    if (!canonicalSourceUrl.empty()) {
      return std::format("{}\n{}", info.trackId, canonicalSourceUrl);
    }
    return std::format("{}\n{}\n{}\n{}", info.trackId, info.title, joinedArtists(info.artists), info.album);
  }

  std::map<std::string, sdbus::Variant> to_dbus_player(const MprisPlayerInfo& info) {
    std::map<std::string, sdbus::Variant> player;
    player["bus_name"] = sdbus::Variant(info.busName);
    player["identity"] = sdbus::Variant(info.identity);
    player["desktop_entry"] = sdbus::Variant(info.desktopEntry);
    player["playback_status"] = sdbus::Variant(info.playbackStatus);
    player["track_id"] = sdbus::Variant(info.trackId);
    player["title"] = sdbus::Variant(info.title);
    player["artists"] = sdbus::Variant(info.artists);
    player["album"] = sdbus::Variant(info.album);
    player["source_url"] = sdbus::Variant(info.sourceUrl);
    player["art_url"] = sdbus::Variant(info.artUrl);
    player["loop_status"] = sdbus::Variant(info.loopStatus);
    player["shuffle"] = sdbus::Variant(info.shuffle);
    player["volume"] = sdbus::Variant(info.volume);
    player["position_us"] = sdbus::Variant(info.positionUs);
    player["length_us"] = sdbus::Variant(info.lengthUs);
    player["can_play"] = sdbus::Variant(info.canPlay);
    player["can_pause"] = sdbus::Variant(info.canPause);
    player["can_go_next"] = sdbus::Variant(info.canGoNext);
    player["can_go_previous"] = sdbus::Variant(info.canGoPrevious);
    player["can_seek"] = sdbus::Variant(info.canSeek);
    return player;
  }

  // Some players report "infinite" stream duration as a sentinel near int64 max.
  // Treat those as unknown length (0) so UI duration/progress stays sane.
  int64_t sanitizeLengthUs(int64_t rawLengthUs) {
    if (rawLengthUs <= 0) {
      return 0;
    }
    constexpr int64_t kInfiniteLengthUsFloor = std::numeric_limits<int64_t>::max() / 1024;
    if (rawLengthUs >= kInfiniteLengthUsFloor) {
      return 0;
    }
    return rawLengthUs;
  }

  constexpr Logger kLog("mpris");
  constexpr auto k_position_retry_interval = std::chrono::milliseconds{1000};
  constexpr auto k_position_candidate_retry_interval = std::chrono::milliseconds{250};
  constexpr auto k_recent_track_change_guard_window = std::chrono::milliseconds{8000};
  constexpr auto k_recent_track_change_slack = std::chrono::milliseconds{750};
  constexpr auto k_position_candidate_match_window = std::chrono::milliseconds{2500};
  constexpr std::int64_t k_position_candidate_tolerance_us = 1500000;
  constexpr std::int64_t k_position_candidate_min_progress_us = 250000;
  constexpr auto k_seek_pause_grace_window = std::chrono::milliseconds{1500};
  constexpr std::int64_t k_paused_same_track_position_jump_tolerance_us = 3000000;
  constexpr auto k_no_signal_pause_recovery_window = std::chrono::milliseconds{6000};
  constexpr std::int64_t k_stale_rebase_clear_slack_us = 5000000;
  constexpr std::int64_t k_previous_track_continuation_slack_us = 15000000;
  constexpr std::int64_t k_pause_recovery_min_jump_us = 10000000;
  constexpr std::int64_t k_track_length_position_slack_us = 5000000;
  constexpr auto k_initial_position_projection_grace_window = std::chrono::milliseconds{1250};
  constexpr std::int64_t k_initial_position_projection_grace_ceiling_us = 5000000;

  bool isPlausibleTrackPosition(std::int64_t positionUs, std::int64_t lengthUs) {
    return lengthUs <= 0 || positionUs <= lengthUs + k_track_length_position_slack_us;
  }

  std::string normalizeFilterToken(std::string_view value) { return StringUtils::toLower(StringUtils::trim(value)); }

} // namespace

MprisService::MprisService(SessionBus& bus)
    : m_bus(bus), m_dbusProxy(sdbus::createProxy(bus.connection(), k_dbus_name, k_dbus_path)) {
  registerControlApi();
  registerBusSignals();
  discoverPlayers();
  scheduleStartupRediscovery();
}

const std::unordered_map<std::string, MprisPlayerInfo>& MprisService::players() const noexcept { return m_players; }

std::vector<MprisPlayerInfo> MprisService::listPlayers() const {
  std::vector<MprisPlayerInfo> result;
  result.reserve(m_players.size());
  for (const auto& [_, player] : m_players) {
    if (isBlacklisted(player)) {
      continue;
    }
    result.push_back(projectedPlayerInfo(player));
  }

  std::ranges::sort(result, [](const MprisPlayerInfo& a, const MprisPlayerInfo& b) { return a.busName < b.busName; });
  return result;
}

std::optional<MprisPlayerInfo> MprisService::activePlayer() const {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    return std::nullopt;
  }

  const auto it = m_players.find(*active);
  if (it == m_players.end()) {
    return std::nullopt;
  }
  return projectedPlayerInfo(it->second);
}

void MprisService::refreshPlayerPosition(const std::string& busName, bool notifyChange) {
  const auto proxyIt = m_playerProxies.find(busName);
  const auto playerIt = m_players.find(busName);
  if (proxyIt == m_playerProxies.end() || playerIt == m_players.end()) {
    return;
  }

  try {
    const auto now = std::chrono::steady_clock::now();
    const auto rawPositionUs =
        proxyIt->second->getProperty("Position").onInterface(k_mpris_player_interface).get<int64_t>();
    auto offsetIt = m_positionOffsetsUs.find(busName);
    std::int64_t offsetUs = offsetIt != m_positionOffsetsUs.end() ? offsetIt->second : 0;
    std::int64_t normalizedUs = std::max<std::int64_t>(0, rawPositionUs - offsetUs);
    const bool hadAuthoritativeSample =
        m_hasAuthoritativePositionSample.contains(busName) && m_hasAuthoritativePositionSample.at(busName);
    const auto trackChangeIt = m_lastLogicalTrackChangeAt.find(busName);
    const bool guardingRecentTrackChange = trackChangeIt != m_lastLogicalTrackChangeAt.end() &&
                                           now - trackChangeIt->second < k_recent_track_change_guard_window;
    const std::int64_t elapsedSinceTrackChangeUs =
        trackChangeIt != m_lastLogicalTrackChangeAt.end()
            ? std::chrono::duration_cast<std::chrono::microseconds>(now - trackChangeIt->second).count()
            : 0;
    const std::int64_t maxPlausibleTrackPositionUs =
        elapsedSinceTrackChangeUs +
        std::chrono::duration_cast<std::chrono::microseconds>(k_recent_track_change_slack).count();
    const auto previousTrackRawIt = m_previousTrackRawPositionUs.find(busName);
    const bool hasPreviousTrackContext = previousTrackRawIt != m_previousTrackRawPositionUs.end();
    const bool looksLikePreviousTrackContinuation =
        hasPreviousTrackContext &&
        std::llabs(rawPositionUs - previousTrackRawIt->second) <= k_previous_track_continuation_slack_us;

    if (offsetUs > 0 && !hasPreviousTrackContext && rawPositionUs + k_stale_rebase_clear_slack_us < offsetUs) {
      offsetIt->second = 0;
      offsetUs = 0;
      normalizedUs = rawPositionUs;
    }

    if (!hadAuthoritativeSample && trackChangeIt != m_lastLogicalTrackChangeAt.end() && offsetUs > 0 &&
        rawPositionUs + k_stale_rebase_clear_slack_us < offsetUs) {
      offsetIt->second = 0;
      offsetUs = 0;
      normalizedUs = rawPositionUs;
    }

    if (!hadAuthoritativeSample && trackChangeIt != m_lastLogicalTrackChangeAt.end() &&
        playerIt->second.playbackStatus != "Stopped" && rawPositionUs > 5'000'000 &&
        normalizedUs > maxPlausibleTrackPositionUs && looksLikePreviousTrackContinuation) {
      offsetIt->second = rawPositionUs;
      if (playerIt->second.positionUs != 0) {
        playerIt->second.positionUs = 0;
        if (notifyChange && m_changeCallback) {
          m_changeCallback();
        }
      }
      if (playerIt->second.playbackStatus != "Stopped") {
        auto& timerId = m_positionResyncTimers[busName];
        timerId = TimerManager::instance().start(timerId, k_position_retry_interval,
                                                 [this, busName]() { refreshPlayerPosition(busName, true); });
      }
      return;
    }

    bool authoritativeSample = false;
    if (normalizedUs > 0) {
      if (guardingRecentTrackChange) {
        authoritativeSample = normalizedUs <= maxPlausibleTrackPositionUs;
      } else {
        authoritativeSample = true;
      }
    } else if (playerIt->second.playbackStatus != "Playing") {
      authoritativeSample = hadAuthoritativeSample;
    }

    if (!authoritativeSample && !hadAuthoritativeSample && trackChangeIt != m_lastLogicalTrackChangeAt.end() &&
        playerIt->second.playbackStatus != "Stopped" && normalizedUs > maxPlausibleTrackPositionUs &&
        rawPositionUs > 5'000'000 && hasPreviousTrackContext && !looksLikePreviousTrackContinuation) {
      authoritativeSample = true;
    }

    if (!m_pendingPositionSignalRefresh[busName] && normalizedUs == 0 && playerIt->second.positionUs > 0 &&
        playerIt->second.playbackStatus != "Stopped") {
      return;
    }

    if (hadAuthoritativeSample && playerIt->second.playbackStatus == "Paused" && normalizedUs > 0) {
      const auto pauseIt = m_recentNoSignalPauseAt.find(busName);
      const bool recoveringRecentPause =
          pauseIt != m_recentNoSignalPauseAt.end() && now - pauseIt->second <= k_no_signal_pause_recovery_window;
      const std::int64_t pausedJumpUs = std::llabs(normalizedUs - playerIt->second.positionUs);
      if (recoveringRecentPause) {
        if (pausedJumpUs < k_pause_recovery_min_jump_us) {
          return;
        }
        playerIt->second.playbackStatus = "Playing";
        m_recentNoSignalPauseAt.erase(pauseIt);
      } else if (pausedJumpUs >= k_paused_same_track_position_jump_tolerance_us) {
        return;
      }
    }

    if (!hadAuthoritativeSample && !authoritativeSample && normalizedUs > 0) {
      const auto candidateIt = m_pendingPositionCandidateUs.find(busName);
      const auto candidateAtIt = m_pendingPositionCandidateAt.find(busName);
      const bool candidateFresh = candidateAtIt != m_pendingPositionCandidateAt.end() &&
                                  now - candidateAtIt->second <= k_position_candidate_match_window;
      bool candidateMatches = candidateIt != m_pendingPositionCandidateUs.end() && candidateFresh &&
                              std::llabs(candidateIt->second - normalizedUs) <= k_position_candidate_tolerance_us;

      if (candidateMatches && playerIt->second.playbackStatus == "Playing") {
        const auto elapsedSinceCandidateUs =
            std::chrono::duration_cast<std::chrono::microseconds>(now - candidateAtIt->second).count();
        const std::int64_t progressUs = normalizedUs - candidateIt->second;
        const std::int64_t maxExpectedProgressUs =
            elapsedSinceCandidateUs +
            std::chrono::duration_cast<std::chrono::microseconds>(k_recent_track_change_slack).count();
        candidateMatches = progressUs >= k_position_candidate_min_progress_us && progressUs <= maxExpectedProgressUs;
      }

      if (!candidateMatches) {
        m_pendingPositionCandidateUs[busName] = normalizedUs;
        m_pendingPositionCandidateMatches[busName] = 0;
        m_pendingPositionCandidateAt[busName] = now;
        if (playerIt->second.playbackStatus == "Playing") {
          auto& timerId = m_positionResyncTimers[busName];
          timerId = TimerManager::instance().start(timerId, k_position_candidate_retry_interval,
                                                   [this, busName]() { refreshPlayerPosition(busName, true); });
        }
        return;
      }

      if (guardingRecentTrackChange && playerIt->second.playbackStatus == "Playing") {
        int& matchCount = m_pendingPositionCandidateMatches[busName];
        ++matchCount;
        if (matchCount < 2) {
          m_pendingPositionCandidateUs[busName] = normalizedUs;
          m_pendingPositionCandidateAt[busName] = now;
          auto& timerId = m_positionResyncTimers[busName];
          timerId = TimerManager::instance().start(timerId, k_position_candidate_retry_interval,
                                                   [this, busName]() { refreshPlayerPosition(busName, true); });
          return;
        }
      }

      authoritativeSample = true;
    }

    if (!authoritativeSample) {
      const bool hasAuthoritativeSample =
          m_hasAuthoritativePositionSample.contains(busName) && m_hasAuthoritativePositionSample.at(busName);
      if (playerIt->second.playbackStatus == "Playing" && !hasAuthoritativeSample) {
        auto& timerId = m_positionResyncTimers[busName];
        timerId = TimerManager::instance().start(timerId, k_position_retry_interval,
                                                 [this, busName]() { refreshPlayerPosition(busName, true); });
      }
      return;
    }

    if (playerIt->second.positionUs != normalizedUs) {
      playerIt->second.positionUs = normalizedUs;
      m_lastPositionSampleAt[busName] = now;
      m_hasAuthoritativePositionSample[busName] = true;
      m_pendingPositionCandidateUs.erase(busName);
      m_pendingPositionCandidateMatches.erase(busName);
      m_pendingPositionCandidateAt.erase(busName);
      if (notifyChange && m_changeCallback) {
        m_changeCallback();
      }
    } else {
      m_lastPositionSampleAt[busName] = now;
      m_hasAuthoritativePositionSample[busName] = true;
      m_pendingPositionCandidateUs.erase(busName);
      m_pendingPositionCandidateMatches.erase(busName);
      m_pendingPositionCandidateAt.erase(busName);
    }

    const bool hasAuthoritativeSample =
        m_hasAuthoritativePositionSample.contains(busName) && m_hasAuthoritativePositionSample.at(busName);
    if (playerIt->second.playbackStatus == "Playing" && !hasAuthoritativeSample) {
      auto& timerId = m_positionResyncTimers[busName];
      timerId = TimerManager::instance().start(timerId, k_position_retry_interval,
                                               [this, busName]() { refreshPlayerPosition(busName, true); });
    }
  } catch (const sdbus::Error& e) {
    kLog.warn("position refresh failed name={} err={}", busName, e.what());
  }
}

MprisPlayerInfo MprisService::projectedPlayerInfo(const MprisPlayerInfo& player) const {
  MprisPlayerInfo projected = player;
  projected.positionUs = projectedPositionUs(player);
  return projected;
}

std::int64_t MprisService::projectedPositionUs(const MprisPlayerInfo& player) const {
  if (player.playbackStatus == "Stopped") {
    return 0;
  }

  const bool hasAuthoritativeSample =
      m_hasAuthoritativePositionSample.contains(player.busName) && m_hasAuthoritativePositionSample.at(player.busName);
  std::int64_t projectedUs = std::max<std::int64_t>(0, player.positionUs);
  if (!hasAuthoritativeSample && player.playbackStatus == "Playing") {
    projectedUs = 0;
  }

  if (player.playbackStatus == "Playing" && hasAuthoritativeSample) {
    if (const auto it = m_lastPositionSampleAt.find(player.busName); it != m_lastPositionSampleAt.end()) {
      const auto trackChangeIt = m_lastLogicalTrackChangeAt.find(player.busName);
      const bool inInitialTrackWindow =
          trackChangeIt != m_lastLogicalTrackChangeAt.end() &&
          std::chrono::steady_clock::now() - trackChangeIt->second <= k_recent_track_change_guard_window;
      const bool suppressInitialProjection =
          inInitialTrackWindow && projectedUs <= k_initial_position_projection_grace_ceiling_us &&
          std::chrono::steady_clock::now() - it->second <= k_initial_position_projection_grace_window;
      if (suppressInitialProjection) {
        if (player.lengthUs > 0) {
          return std::clamp<std::int64_t>(projectedUs, 0, player.lengthUs);
        }
        return projectedUs;
      }

      const auto elapsedUs =
          std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - it->second).count();
      if (elapsedUs > 0) {
        projectedUs += elapsedUs;
      }
    }
  }

  if (player.lengthUs > 0) {
    projectedUs = std::clamp<std::int64_t>(projectedUs, 0, player.lengthUs);
  }
  return projectedUs;
}

void MprisService::refreshPlayers() {
  kLog.debug("manual player refresh requested players_cached={}", m_players.size());
  discoverPlayers();
}

void MprisService::registerIpc(IpcService& ipc) {
  ipc.registerHandler(
      "media",
      [this](const std::string& args) -> std::string {
        const auto parts = noctalia::ipc::splitWords(args);
        if (parts.size() != 1) {
          return "error: media requires exactly one action <next|previous|toggle>\n";
        }

        const std::string& action = parts[0];
        if (action == "next") {
          return nextActive() ? "ok\n" : "error: no active player or Next unsupported\n";
        }
        if (action == "previous") {
          return previousActive() ? "ok\n" : "error: no active player or Previous unsupported\n";
        }
        if (action == "toggle" || action == "playPause" || action == "play-pause") {
          return playPauseActive() ? "ok\n" : "error: no active player or PlayPause unsupported\n";
        }

        return "error: invalid media action (use next, previous, toggle)\n";
      },
      "media <next|previous|toggle>", "Control active media playback");
}

bool MprisService::playPause(const std::string& busName) {
  const auto it = m_players.find(busName);
  if (it == m_players.end()) {
    return false;
  }
  if (!canInvoke(it->second, "PlayPause")) {
    return false;
  }
  return callPlayerMethod(busName, "PlayPause");
}

bool MprisService::next(const std::string& busName) {
  const auto it = m_players.find(busName);
  if (it == m_players.end()) {
    return false;
  }
  if (!canInvoke(it->second, "Next")) {
    return false;
  }
  return callPlayerMethod(busName, "Next");
}

bool MprisService::previous(const std::string& busName) {
  const auto it = m_players.find(busName);
  if (it == m_players.end()) {
    return false;
  }
  if (!canInvoke(it->second, "Previous")) {
    return false;
  }
  return callPlayerMethod(busName, "Previous");
}

bool MprisService::playPauseActive() {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    return false;
  }
  return playPause(*active);
}

bool MprisService::nextActive() {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    return false;
  }
  return next(*active);
}

bool MprisService::previousActive() {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    return false;
  }
  return previous(*active);
}

bool MprisService::seek(const std::string& busName, int64_t offsetUs) {
  const auto it = m_players.find(busName);
  if (it == m_players.end() || !it->second.canSeek) {
    return false;
  }

  const auto proxyIt = m_playerProxies.find(busName);
  if (proxyIt == m_playerProxies.end()) {
    return false;
  }

  try {
    proxyIt->second->callMethod("Seek").onInterface(k_mpris_player_interface).withArguments(offsetUs);
    m_lastSeekCommandAt[busName] = std::chrono::steady_clock::now();
    addOrRefreshPlayer(busName);
    return true;
  } catch (const sdbus::Error& e) {
    kLog.warn("seek failed name={} err={}", busName, e.what());
    return false;
  }
}

bool MprisService::seekActive(int64_t offsetUs) {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    return false;
  }
  return seek(*active, offsetUs);
}

bool MprisService::setPosition(const std::string& busName, int64_t positionUs) {
  const auto it = m_players.find(busName);
  if (it == m_players.end() || !it->second.canSeek) {
    return false;
  }

  const auto proxyIt = m_playerProxies.find(busName);
  if (proxyIt == m_playerProxies.end()) {
    return false;
  }

  auto fallback_seek = [&]() {
    int64_t currentPositionUs = it->second.positionUs;
    try {
      const sdbus::Variant positionValue =
          proxyIt->second->getProperty("Position").onInterface(k_mpris_player_interface);
      currentPositionUs = positionValue.get<int64_t>();
    } catch (const sdbus::Error& e) {
      kLog.warn("position refresh failed name={} err={}, using cached value", busName, e.what());
    }

    const int64_t offsetUs = positionUs - currentPositionUs;
    if (offsetUs == 0) {
      return true;
    }
    return seek(busName, offsetUs);
  };

  const bool preferRelativeSeek = it->second.trackId.empty() || busName.find("spotify") != std::string::npos;
  if (preferRelativeSeek) {
    // Some players don't expose track_id consistently; emulate absolute position with Seek.
    kLog.debug("mpris set-position using relative Seek fallback for {}", busName);
    return fallback_seek();
  }

  try {
    proxyIt->second->callMethod("SetPosition")
        .onInterface(k_mpris_player_interface)
        .withArguments(sdbus::ObjectPath{it->second.trackId}, positionUs);
    m_lastSeekCommandAt[busName] = std::chrono::steady_clock::now();
    addOrRefreshPlayer(busName);
    return true;
  } catch (const sdbus::Error& e) {
    kLog.warn("set-position failed name={} err={}, falling back to Seek", busName, e.what());
    return fallback_seek();
  }
}

bool MprisService::setPositionActive(int64_t positionUs) {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    return false;
  }
  return setPosition(*active, positionUs);
}

bool MprisService::setVolume(const std::string& busName, double volume) {
  const auto it = m_players.find(busName);
  if (it == m_players.end()) {
    return false;
  }

  const auto proxyIt = m_playerProxies.find(busName);
  if (proxyIt == m_playerProxies.end()) {
    return false;
  }

  try {
    proxyIt->second->setProperty("Volume").onInterface(k_mpris_player_interface).toValue(volume);
    addOrRefreshPlayer(busName);
    return true;
  } catch (const sdbus::Error& e) {
    kLog.warn("set-volume failed name={} err={}", busName, e.what());
    return false;
  }
}

bool MprisService::setVolumeActive(double volume) {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    return false;
  }
  return setVolume(*active, volume);
}

bool MprisService::setShuffle(const std::string& busName, bool shuffle) {
  const auto it = m_players.find(busName);
  if (it == m_players.end()) {
    return false;
  }

  const auto proxyIt = m_playerProxies.find(busName);
  if (proxyIt == m_playerProxies.end()) {
    return false;
  }

  try {
    proxyIt->second->setProperty("Shuffle").onInterface(k_mpris_player_interface).toValue(shuffle);
    addOrRefreshPlayer(busName);
    return true;
  } catch (const sdbus::Error& e) {
    kLog.warn("set-shuffle failed name={} err={}", busName, e.what());
    return false;
  }
}

bool MprisService::setShuffleActive(bool shuffle) {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    return false;
  }
  return setShuffle(*active, shuffle);
}

bool MprisService::setLoopStatus(const std::string& busName, std::string loopStatus) {
  const auto it = m_players.find(busName);
  if (it == m_players.end()) {
    return false;
  }

  const auto proxyIt = m_playerProxies.find(busName);
  if (proxyIt == m_playerProxies.end()) {
    return false;
  }

  try {
    proxyIt->second->setProperty("LoopStatus").onInterface(k_mpris_player_interface).toValue(std::move(loopStatus));
    addOrRefreshPlayer(busName);
    return true;
  } catch (const sdbus::Error& e) {
    kLog.warn("set-loop-status failed name={} err={}", busName, e.what());
    return false;
  }
}

bool MprisService::setLoopStatusActive(std::string loopStatus) {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    return false;
  }
  return setLoopStatus(*active, std::move(loopStatus));
}

std::optional<int64_t> MprisService::position(const std::string& busName) const {
  const auto it = m_players.find(busName);
  if (it == m_players.end()) {
    return std::nullopt;
  }
  return projectedPositionUs(it->second);
}

std::optional<int64_t> MprisService::positionActive() const {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    return std::nullopt;
  }
  return position(*active);
}

std::optional<double> MprisService::volume(const std::string& busName) const {
  const auto it = m_players.find(busName);
  if (it == m_players.end()) {
    return std::nullopt;
  }
  return it->second.volume;
}

std::optional<double> MprisService::volumeActive() const {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    return std::nullopt;
  }
  return volume(*active);
}

std::optional<bool> MprisService::shuffle(const std::string& busName) const {
  const auto it = m_players.find(busName);
  if (it == m_players.end()) {
    return std::nullopt;
  }
  return it->second.shuffle;
}

std::optional<bool> MprisService::shuffleActive() const {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    return std::nullopt;
  }
  return shuffle(*active);
}

std::optional<std::string> MprisService::loopStatus(const std::string& busName) const {
  const auto it = m_players.find(busName);
  if (it == m_players.end()) {
    return std::nullopt;
  }
  return it->second.loopStatus;
}

std::optional<std::string> MprisService::loopStatusActive() const {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    return std::nullopt;
  }
  return loopStatus(*active);
}

bool MprisService::setPinnedPlayerPreference(const std::string& busName) {
  const auto it = m_players.find(busName);
  if (it == m_players.end() || isBlacklisted(it->second)) {
    return false;
  }

  const auto previousActive = activePlayer();
  m_pinnedPlayerPreference = busName;
  syncSignals(previousActive);
  if (m_changeCallback) {
    m_changeCallback();
  }
  return true;
}

void MprisService::clearPinnedPlayerPreference() {
  const auto previousActive = activePlayer();
  m_pinnedPlayerPreference.reset();
  syncSignals(previousActive);
  if (m_changeCallback) {
    m_changeCallback();
  }
}

void MprisService::setPreferredPlayers(std::vector<std::string> preferredBusNames) {
  std::unordered_set<std::string> seen;
  std::vector<std::string> normalized;
  normalized.reserve(preferredBusNames.size());

  for (auto& busName : preferredBusNames) {
    if (busName.empty()) {
      continue;
    }
    if (seen.insert(busName).second) {
      normalized.push_back(std::move(busName));
    }
  }

  const auto previousActive = activePlayer();
  m_preferredPlayers = std::move(normalized);
  syncSignals(previousActive);
  if (m_changeCallback) {
    m_changeCallback();
  }
}

void MprisService::setBlacklist(std::vector<std::string> blacklist) {
  std::unordered_set<std::string> seen;
  std::vector<std::string> normalized;
  normalized.reserve(blacklist.size());

  for (const auto& raw : blacklist) {
    const std::string token = normalizeFilterToken(raw);
    if (token.empty()) {
      continue;
    }
    if (seen.insert(token).second) {
      normalized.push_back(token);
    }
  }

  if (m_blacklist == normalized) {
    return;
  }

  const auto previousActive = activePlayer();
  m_blacklist = std::move(normalized);

  if (m_pinnedPlayerPreference.has_value()) {
    const auto it = m_players.find(*m_pinnedPlayerPreference);
    if (it == m_players.end() || isBlacklisted(it->second)) {
      m_pinnedPlayerPreference.reset();
    }
  }

  emitPlayersChanged();
  syncSignals(previousActive);
  if (m_changeCallback) {
    m_changeCallback();
  }
}

void MprisService::setChangeCallback(std::function<void()> callback) {
  m_changeCallback = std::move(callback);
  if (m_changeCallback && !m_players.empty()) {
    m_changeCallback();
  }
}

std::optional<std::string> MprisService::pinnedPlayerPreference() const { return m_pinnedPlayerPreference; }

const std::vector<std::string>& MprisService::preferredPlayers() const noexcept { return m_preferredPlayers; }

const std::vector<std::string>& MprisService::blacklist() const noexcept { return m_blacklist; }

void MprisService::registerControlApi() {
  m_bus.connection().requestName(k_noctalia_mpris_bus_name);
  m_controlObject = sdbus::createObject(m_bus.connection(), k_noctalia_mpris_object_path);

  m_controlObject
      ->addVTable(
          sdbus::registerSignal("PlayersChanged")
              .withParameters<std::vector<std::map<std::string, sdbus::Variant>>>("players"),

          sdbus::registerSignal("ActivePlayerChanged")
              .withParameters<bool, std::map<std::string, sdbus::Variant>>("found", "player"),

          sdbus::registerSignal("TrackChanged")
              .withParameters<std::string, std::map<std::string, sdbus::Variant>>("player_bus_name", "player"),

          sdbus::registerMethod("GetPlayers").withOutputParamNames("players").implementedAs([this]() {
            std::vector<std::map<std::string, sdbus::Variant>> players;
            for (const auto& player : listPlayers()) {
              players.push_back(to_dbus_player(player));
            }
            return players;
          }),

          sdbus::registerMethod("GetActivePlayer").withOutputParamNames("found", "player").implementedAs([this]() {
            const auto active = activePlayer();
            if (!active.has_value()) {
              return std::make_tuple(false, std::map<std::string, sdbus::Variant>{});
            }
            return std::make_tuple(true, to_dbus_player(*active));
          }),

          sdbus::registerMethod("SetActivePlayerPreference")
              .withInputParamNames("player_bus_name")
              .withOutputParamNames("success")
              .implementedAs([this](const std::string& busName) { return onSetActivePlayerPreference(busName); }),

          sdbus::registerMethod("ClearActivePlayerPreference").withOutputParamNames("success").implementedAs([this]() {
            return onClearActivePlayerPreference();
          }),

          sdbus::registerMethod("SetPreferredPlayers")
              .withInputParamNames("preferred_bus_names")
              .withOutputParamNames("success")
              .implementedAs([this](const std::vector<std::string>& preferredBusNames) {
                return onSetPreferredPlayers(preferredBusNames);
              }),

          sdbus::registerMethod("GetPlayerPreferences")
              .withOutputParamNames("has_pinned", "pinned_bus_name", "preferred_bus_names")
              .implementedAs([this]() { return onGetPlayerPreferences(); }),

          sdbus::registerMethod("GetPositionPlayer")
              .withInputParamNames("player_bus_name")
              .withOutputParamNames("position_us")
              .implementedAs([this](const std::string& busName) { return onGetPositionPlayer(busName); }),

          sdbus::registerMethod("GetPositionActive").withOutputParamNames("position_us").implementedAs([this]() {
            return onGetPositionActive();
          }),

          sdbus::registerMethod("GetVolumePlayer")
              .withInputParamNames("player_bus_name")
              .withOutputParamNames("volume")
              .implementedAs([this](const std::string& busName) { return onGetVolumePlayer(busName); }),

          sdbus::registerMethod("GetVolumeActive").withOutputParamNames("volume").implementedAs([this]() {
            return onGetVolumeActive();
          }),

          sdbus::registerMethod("SetVolumePlayer")
              .withInputParamNames("player_bus_name", "volume")
              .withOutputParamNames("success")
              .implementedAs(
                  [this](const std::string& busName, double volume) { return onSetVolumePlayer(busName, volume); }),

          sdbus::registerMethod("SetVolumeActive")
              .withInputParamNames("volume")
              .withOutputParamNames("success")
              .implementedAs([this](double volume) { return onSetVolumeActive(volume); }),

          sdbus::registerMethod("GetShufflePlayer")
              .withInputParamNames("player_bus_name")
              .withOutputParamNames("shuffle")
              .implementedAs([this](const std::string& busName) { return onGetShufflePlayer(busName); }),

          sdbus::registerMethod("GetShuffleActive").withOutputParamNames("shuffle").implementedAs([this]() {
            return onGetShuffleActive();
          }),

          sdbus::registerMethod("SetShufflePlayer")
              .withInputParamNames("player_bus_name", "shuffle")
              .withOutputParamNames("success")
              .implementedAs(
                  [this](const std::string& busName, bool shuffle) { return onSetShufflePlayer(busName, shuffle); }),

          sdbus::registerMethod("SetShuffleActive")
              .withInputParamNames("shuffle")
              .withOutputParamNames("success")
              .implementedAs([this](bool shuffle) { return onSetShuffleActive(shuffle); }),

          sdbus::registerMethod("GetLoopStatusPlayer")
              .withInputParamNames("player_bus_name")
              .withOutputParamNames("loop_status")
              .implementedAs([this](const std::string& busName) { return onGetLoopStatusPlayer(busName); }),

          sdbus::registerMethod("GetLoopStatusActive").withOutputParamNames("loop_status").implementedAs([this]() {
            return onGetLoopStatusActive();
          }),

          sdbus::registerMethod("SetLoopStatusPlayer")
              .withInputParamNames("player_bus_name", "loop_status")
              .withOutputParamNames("success")
              .implementedAs([this](const std::string& busName, const std::string& loopStatus) {
                return onSetLoopStatusPlayer(busName, loopStatus);
              }),

          sdbus::registerMethod("SetLoopStatusActive")
              .withInputParamNames("loop_status")
              .withOutputParamNames("success")
              .implementedAs([this](const std::string& loopStatus) { return onSetLoopStatusActive(loopStatus); }),

          sdbus::registerMethod("SeekPlayer")
              .withInputParamNames("player_bus_name", "offset_us")
              .withOutputParamNames("success")
              .implementedAs(
                  [this](const std::string& busName, int64_t offsetUs) { return onSeekPlayer(busName, offsetUs); }),

          sdbus::registerMethod("SeekActive")
              .withInputParamNames("offset_us")
              .withOutputParamNames("success")
              .implementedAs([this](int64_t offsetUs) { return onSeekActive(offsetUs); }),

          sdbus::registerMethod("SetPositionPlayer")
              .withInputParamNames("player_bus_name", "position_us")
              .withOutputParamNames("success")
              .implementedAs([this](const std::string& busName, int64_t positionUs) {
                return onSetPositionPlayer(busName, positionUs);
              }),

          sdbus::registerMethod("SetPositionActive")
              .withInputParamNames("position_us")
              .withOutputParamNames("success")
              .implementedAs([this](int64_t positionUs) { return onSetPositionActive(positionUs); }),

          sdbus::registerMethod("PlayPausePlayer")
              .withInputParamNames("player_bus_name")
              .withOutputParamNames("success")
              .implementedAs([this](const std::string& busName) { return onPlayPausePlayer(busName); }),

          sdbus::registerMethod("NextPlayer")
              .withInputParamNames("player_bus_name")
              .withOutputParamNames("success")
              .implementedAs([this](const std::string& busName) { return onNextPlayer(busName); }),

          sdbus::registerMethod("PreviousPlayer")
              .withInputParamNames("player_bus_name")
              .withOutputParamNames("success")
              .implementedAs([this](const std::string& busName) { return onPreviousPlayer(busName); }),

          sdbus::registerMethod("PlayPauseActive").withOutputParamNames("success").implementedAs([this]() {
            return onPlayPauseActive();
          }),

          sdbus::registerMethod("NextActive").withOutputParamNames("success").implementedAs([this]() {
            return onNextActive();
          }),

          sdbus::registerMethod("PreviousActive").withOutputParamNames("success").implementedAs([this]() {
            return onPreviousActive();
          }))
      .forInterface(k_noctalia_mpris_interface);
}

void MprisService::emitPlayersChanged() {
  std::vector<std::map<std::string, sdbus::Variant>> players;
  for (const auto& player : listPlayers()) {
    players.push_back(to_dbus_player(player));
  }

  m_controlObject->emitSignal("PlayersChanged").onInterface(k_noctalia_mpris_interface).withArguments(players);
}

void MprisService::emitActivePlayerChanged() {
  const auto active = activePlayer();
  if (!active.has_value()) {
    m_controlObject->emitSignal("ActivePlayerChanged")
        .onInterface(k_noctalia_mpris_interface)
        .withArguments(false, std::map<std::string, sdbus::Variant>{});
    return;
  }

  m_controlObject->emitSignal("ActivePlayerChanged")
      .onInterface(k_noctalia_mpris_interface)
      .withArguments(true, to_dbus_player(*active));
}

void MprisService::emitTrackChanged(const MprisPlayerInfo& player) {
  m_controlObject->emitSignal("TrackChanged")
      .onInterface(k_noctalia_mpris_interface)
      .withArguments(player.busName, to_dbus_player(player));
}

void MprisService::syncSignals(const std::optional<MprisPlayerInfo>& previousActive) {
  const auto current_active = activePlayer();
  const std::string current_active_name = current_active.has_value() ? current_active->busName : std::string{};

  if (current_active_name != m_lastEmittedActivePlayer) {
    emitActivePlayerChanged();
    m_lastEmittedActivePlayer = current_active_name;
  }

  if (previousActive.has_value() && current_active.has_value() && previousActive->busName == current_active->busName &&
      previousActive->title != current_active->title) {
    emitTrackChanged(*current_active);
  }
}

void MprisService::registerBusSignals() {
  m_dbusProxy->uponSignal("NameOwnerChanged")
      .onInterface(k_dbus_interface)
      .call([this](const std::string& name, const std::string& old_owner, const std::string& new_owner) {
        if (!is_mpris_bus_name(name)) {
          return;
        }

        kLog.debug("name owner changed name={} old_owner=\"{}\" new_owner=\"{}\"", name, old_owner, new_owner);

        if (new_owner.empty()) {
          removePlayer(name);
          return;
        }

        if (old_owner.empty()) {
          addOrRefreshPlayer(name);
          return;
        }

        addOrRefreshPlayer(name);
      });
}

void MprisService::discoverPlayers() {
  std::vector<std::string> names;
  try {
    m_dbusProxy->callMethod("ListNames").onInterface(k_dbus_interface).storeResultsTo(names);
  } catch (const sdbus::Error& e) {
    kLog.warn("discover players failed err={}", e.what());
    scheduleRecoveryDiscovery();
    return;
  }

  for (const auto& name : names) {
    if (is_mpris_bus_name(name)) {
      // kLog.debug("discover found mpris bus={}", name);
      addOrRefreshPlayer(name);
    }
  }

  // kLog.debug("discover players listed={} cached_after={}", names.size(), m_players.size());
}

void MprisService::scheduleStartupRediscovery() {
  if (m_startupRediscoveryPassesRemaining <= 0) {
    return;
  }

  DeferredCall::callLater([this]() {
    discoverPlayers();
    --m_startupRediscoveryPassesRemaining;
    if (m_startupRediscoveryPassesRemaining > 0) {
      scheduleStartupRediscovery();
    }
  });
}

void MprisService::scheduleRecoveryDiscovery() {
  if (m_recoveryDiscoveryScheduled) {
    return;
  }

  m_recoveryDiscoveryScheduled = true;
  DeferredCall::callLater([this]() {
    m_recoveryDiscoveryScheduled = false;
    discoverPlayers();
  });
}

void MprisService::addOrRefreshPlayer(const std::string& busName) {
  const auto previousActive = activePlayer();

  auto [proxyIt, inserted] = m_playerProxies.emplace(
      busName, sdbus::createProxy(m_bus.connection(), sdbus::ServiceName{busName}, k_mpris_path));

  if (inserted) {
    proxyIt->second->uponSignal("PropertiesChanged")
        .onInterface(k_properties_interface)
        .call([this, busName](const std::string& interface_name,
                              const std::map<std::string, sdbus::Variant>& changed_properties,
                              const std::vector<std::string>& invalidated_properties) {
          if (interface_name == k_mpris_root_interface || interface_name == k_mpris_player_interface) {
            const bool metadataChanged =
                changed_properties.contains("Metadata") ||
                std::ranges::find(invalidated_properties, std::string{"Metadata"}) != invalidated_properties.end();
            const bool positionChanged =
                changed_properties.contains("Position") ||
                std::ranges::find(invalidated_properties, std::string{"Position"}) != invalidated_properties.end();
            if (positionChanged) {
              m_pendingPositionSignalRefresh[busName] = true;
            }
            const auto now = std::chrono::steady_clock::now();
            if (metadataChanged) {
              // Metadata updates often arrive in short bursts (first partial, then full artwork/title payload).
              // Never debounce these or we can get stuck on stale app/logo art after rapid stream switches.
              m_lastPropertiesUpdate[busName] = now;
              addOrRefreshPlayer(busName);
              return;
            }

            const auto last_it = m_lastPropertiesUpdate.find(busName);
            if (last_it != m_lastPropertiesUpdate.end() && now - last_it->second < k_properties_debounce_window) {
              return;
            }
            m_lastPropertiesUpdate[busName] = now;
            addOrRefreshPlayer(busName);
          }
        });

    proxyIt->second->uponSignal("Seeked").onInterface(k_mpris_player_interface).call([this, busName](int64_t posUs) {
      auto playerIt = m_players.find(busName);
      if (playerIt == m_players.end()) {
        return;
      }

      const auto now = std::chrono::steady_clock::now();
      auto offsetIt = m_positionOffsetsUs.find(busName);
      std::int64_t offsetUs = offsetIt != m_positionOffsetsUs.end() ? offsetIt->second : 0;
      std::int64_t normalizedUs = std::max<std::int64_t>(0, posUs - offsetUs);
      const std::int64_t previousPosUs = playerIt->second.positionUs;
      const auto previousTrackRawIt = m_previousTrackRawPositionUs.find(busName);
      const bool looksLikePreviousTrackContinuation =
          previousTrackRawIt != m_previousTrackRawPositionUs.end() &&
          std::llabs(posUs - previousTrackRawIt->second) <= k_previous_track_continuation_slack_us;

      if (looksLikePreviousTrackContinuation) {
        return;
      }

      if (offsetUs > 0) {
        offsetIt->second = 0;
        offsetUs = 0;
        normalizedUs = std::max<std::int64_t>(0, posUs);
      }

      if (!isPlausibleTrackPosition(normalizedUs, playerIt->second.lengthUs)) {
        return;
      }

      if (playerIt->second.playbackStatus == "Paused" && normalizedUs > 0) {
        const auto pauseIt = m_recentNoSignalPauseAt.find(busName);
        const bool recoveringRecentPause =
            pauseIt != m_recentNoSignalPauseAt.end() && now - pauseIt->second <= k_no_signal_pause_recovery_window;
        const std::int64_t pausedJumpUs = std::llabs(normalizedUs - previousPosUs);
        if (pausedJumpUs >= k_pause_recovery_min_jump_us) {
          playerIt->second.playbackStatus = "Playing";
          if (recoveringRecentPause) {
            m_recentNoSignalPauseAt.erase(pauseIt);
          }
        }
      }

      playerIt->second.positionUs = normalizedUs;
      m_hasAuthoritativePositionSample[busName] = true;
      m_lastPositionSampleAt[busName] = now;
      m_previousTrackRawPositionUs.erase(busName);
      m_pendingPositionCandidateUs.erase(busName);
      m_pendingPositionCandidateMatches.erase(busName);
      m_pendingPositionCandidateAt.erase(busName);
      if (m_changeCallback) {
        m_changeCallback();
      }
    });
  }

  try {
    const bool hadPositionSignal = m_pendingPositionSignalRefresh[busName];
    m_pendingPositionSignalRefresh[busName] = false;
    const MprisPlayerInfo info = readPlayerInfo(*proxyIt->second, busName);
    const auto now = std::chrono::steady_clock::now();
    // kLog.debug(
    //     "queried player name={} identity=\"{}\" status=\"{}\" title=\"{}\" artist=\"{}\" track_id=\"{}\"
    //     art_url=\"{}\"", info.busName, info.identity, info.playbackStatus, info.title, primary_artist(info.artists),
    //     info.trackId, info.artUrl);
    if (info.artUrl.empty()) {
      const auto metadata = get_metadata_or(*proxyIt->second);
      // kLog.debug("queried player missing art url name={} metadata_keys=[{}]", info.busName, joinKeys(metadata));
    }
    if (info.playbackStatus == "Playing") {
      m_lastActivePlayer = busName;
      m_lastPlayingUpdate[busName] = now;
    }
    if (hasStrongNowPlayingMetadata(info)) {
      m_lastStrongMetadataUpdate[busName] = now;
    }

    const auto existing = m_players.find(busName);
    if (existing == m_players.end()) {
      MprisPlayerInfo initial = info;
      if (!hadPositionSignal) {
        initial.positionUs = 0;
      }
      m_logicalTrackSignatures[busName] = logicalTrackSignature(initial);
      m_positionOffsetsUs[busName] = 0;
      m_lastLogicalTrackChangeAt[busName] = now;
      m_lastPositionSampleAt[busName] = now;
      m_hasAuthoritativePositionSample[busName] = false;
      m_previousTrackRawPositionUs.erase(busName);
      m_pendingPositionCandidateUs.erase(busName);
      m_pendingPositionCandidateMatches.erase(busName);
      m_pendingPositionCandidateAt.erase(busName);
      // kLog.debug("added player name={} identity=\"{}\" status={} title=\"{}\" artist=\"{}\" art_url=\"{}\"",
      //            info.busName, info.identity, info.playbackStatus, info.title, primary_artist(info.artists),
      //            info.artUrl);
      m_players.emplace(busName, std::move(initial));
      emitPlayersChanged();
      syncSignals(previousActive);
      if (m_changeCallback) {
        m_changeCallback();
      }

      if (info.playbackStatus != "Stopped" || info.positionUs > 0) {
        DeferredCall::callLater([this, busName]() { refreshPlayerPosition(busName, true); });
        auto& timerId = m_positionResyncTimers[busName];
        timerId = TimerManager::instance().start(timerId, k_position_retry_interval,
                                                 [this, busName]() { refreshPlayerPosition(busName, true); });
      }
      return;
    }

    if (existing->second != info) {
      const MprisPlayerInfo previous_info = existing->second;

      MprisPlayerInfo merged = info;
      if (merged.artUrl.empty() && !previous_info.artUrl.empty()) {
        merged.artUrl = previous_info.artUrl;
      }

      const bool incomingSnapshotEmpty = merged.playbackStatus.empty() && merged.trackId.empty() &&
                                         merged.title.empty() && merged.artists.empty() && merged.album.empty() &&
                                         merged.sourceUrl.empty() && merged.artUrl.empty() && merged.lengthUs == 0;
      if (incomingSnapshotEmpty) {
        merged = previous_info;
      }

      const bool previousStrong = hasStrongNowPlayingMetadata(previous_info) || !previous_info.artUrl.empty();
      const bool incomingWeak = !hasStrongNowPlayingMetadata(info);
      const auto strongIt = m_lastStrongMetadataUpdate.find(busName);
      const bool withinStabilizeWindow =
          strongIt != m_lastStrongMetadataUpdate.end() && now - strongIt->second < k_metadata_stabilize_window;
      const auto seekCommandIt = m_lastSeekCommandAt.find(busName);
      const bool recentLocalSeek =
          seekCommandIt != m_lastSeekCommandAt.end() && now - seekCommandIt->second <= k_seek_pause_grace_window;

      if (merged.playbackStatus == "Playing" && previousStrong && incomingWeak && withinStabilizeWindow &&
          recentLocalSeek) {
        const std::string incomingArtUrl = info.artUrl;
        const std::string incomingSourceUrl = info.sourceUrl;
        merged.trackId = previous_info.trackId;
        merged.title = previous_info.title;
        merged.artists = previous_info.artists;
        merged.album = previous_info.album;
        merged.sourceUrl = previous_info.sourceUrl;
        merged.artUrl = previous_info.artUrl;
        if (!incomingArtUrl.empty()) {
          merged.artUrl = incomingArtUrl;
        }
        if (!incomingSourceUrl.empty()) {
          merged.sourceUrl = incomingSourceUrl;
        }
      }

      const std::string newSignature = logicalTrackSignature(merged);
      const auto signatureIt = m_logicalTrackSignatures.find(busName);
      const std::string previousSignature =
          signatureIt != m_logicalTrackSignatures.end() ? signatureIt->second : logicalTrackSignature(previous_info);

      auto offsetIt = m_positionOffsetsUs.find(busName);
      if (offsetIt == m_positionOffsetsUs.end()) {
        offsetIt = m_positionOffsetsUs.emplace(busName, 0).first;
      }

      const bool previousPositionAuthoritative =
          m_hasAuthoritativePositionSample.contains(busName) && m_hasAuthoritativePositionSample.at(busName);

      const bool logicalTrackChanged = !newSignature.empty() && previousSignature != newSignature;
      const bool playbackStatusChanged = previous_info.playbackStatus != merged.playbackStatus;

      if (previousPositionAuthoritative && !logicalTrackChanged && !hadPositionSignal &&
          previous_info.playbackStatus == "Playing" && merged.playbackStatus == "Paused" && previous_info.canSeek) {
        m_recentNoSignalPauseAt[busName] = now;
        const auto sampleIt = m_lastPositionSampleAt.find(busName);
        const bool withinSeekPauseGrace =
            sampleIt != m_lastPositionSampleAt.end() && now - sampleIt->second <= k_seek_pause_grace_window;
        if (withinSeekPauseGrace && recentLocalSeek) {
          merged.playbackStatus = previous_info.playbackStatus;
        }
      } else if (merged.playbackStatus != "Paused") {
        m_recentNoSignalPauseAt.erase(busName);
      }

      bool preservedNormalizedPosition = false;
      if (previousPositionAuthoritative && !logicalTrackChanged && !hadPositionSignal &&
          previous_info.playbackStatus != "Stopped" && merged.playbackStatus != "Stopped" &&
          previous_info.positionUs != merged.positionUs) {
        bool preservePreviousPosition = playbackStatusChanged;
        if (!preservePreviousPosition) {
          const auto sampleIt = m_lastPositionSampleAt.find(busName);
          const std::int64_t elapsedSinceSampleUs =
              sampleIt != m_lastPositionSampleAt.end()
                  ? std::chrono::duration_cast<std::chrono::microseconds>(now - sampleIt->second).count()
                  : 0;
          const std::int64_t rawDeltaUs = std::llabs(merged.positionUs - previous_info.positionUs);
          const std::int64_t maxReasonableDeltaUs = std::max<std::int64_t>(5'000'000, elapsedSinceSampleUs + 2'000'000);
          preservePreviousPosition = rawDeltaUs > maxReasonableDeltaUs;
          if (!preservePreviousPosition && previous_info.playbackStatus == "Paused" &&
              merged.playbackStatus == "Paused") {
            preservePreviousPosition = rawDeltaUs > k_paused_same_track_position_jump_tolerance_us;
          }
        }

        if (preservePreviousPosition) {
          merged.positionUs = previous_info.positionUs;
          preservedNormalizedPosition = true;
        }
      }
      if (previousPositionAuthoritative && !logicalTrackChanged && !hadPositionSignal && merged.positionUs == 0 &&
          previous_info.positionUs > 0 && previous_info.playbackStatus != "Stopped" &&
          merged.playbackStatus != "Stopped") {
        merged.positionUs = previous_info.positionUs;
        preservedNormalizedPosition = true;
      }
      if (logicalTrackChanged) {
        const std::int64_t previousOffset = offsetIt->second;
        const std::int64_t previousNormalized = std::max<std::int64_t>(0, previous_info.positionUs - previousOffset);
        const std::int64_t previousRawPositionUs = std::max<std::int64_t>(0, previous_info.positionUs + previousOffset);
        m_previousTrackRawPositionUs[busName] = previousRawPositionUs;
        offsetIt->second = 0;
        const bool looksLikePreviousTrackContinuation =
            merged.positionUs > 5'000'000 && previousNormalized > 5'000'000 &&
            std::llabs(merged.positionUs - previousRawPositionUs) <= k_previous_track_continuation_slack_us;
        if (looksLikePreviousTrackContinuation) {
          offsetIt->second = merged.positionUs;
        }

        m_lastLogicalTrackChangeAt[busName] = now;
        m_hasAuthoritativePositionSample[busName] = false;
        m_recentNoSignalPauseAt.erase(busName);
        m_lastPositionSampleAt[busName] = now;
        m_pendingPositionCandidateUs.erase(busName);
        m_pendingPositionCandidateMatches.erase(busName);
        m_pendingPositionCandidateAt.erase(busName);
      }

      if (!preservedNormalizedPosition) {
        const std::int64_t offsetUs = offsetIt->second;
        merged.positionUs = std::max<std::int64_t>(0, merged.positionUs - offsetUs);
      }
      m_logicalTrackSignatures[busName] = newSignature;
      if (hadPositionSignal) {
        m_hasAuthoritativePositionSample[busName] = true;
      }
      if (previous_info.positionUs != merged.positionUs || previous_info.playbackStatus != merged.playbackStatus) {
        m_lastPositionSampleAt[busName] = now;
      }

      existing->second = merged;
      // kLog.debug("updated player name={} status={} title=\"{}\" artist=\"{}\" art_url=\"{}\"", merged.busName,
      //            merged.playbackStatus, merged.title, primary_artist(merged.artists), merged.artUrl);

      const bool trackChanged = previous_info.title != merged.title || previous_info.album != merged.album ||
                                previous_info.artists != merged.artists || previous_info.artUrl != merged.artUrl ||
                                previous_info.sourceUrl != merged.sourceUrl ||
                                previous_info.trackId != merged.trackId || previous_info.lengthUs != merged.lengthUs;
      const bool significantChanged =
          trackChanged || previous_info.identity != merged.identity ||
          previous_info.playbackStatus != merged.playbackStatus || previous_info.loopStatus != merged.loopStatus ||
          previous_info.shuffle != merged.shuffle || previous_info.canGoPrevious != merged.canGoPrevious ||
          previous_info.canGoNext != merged.canGoNext || previous_info.canPlay != merged.canPlay ||
          previous_info.canPause != merged.canPause || previous_info.canSeek != merged.canSeek;

      if (trackChanged || previous_info.playbackStatus != merged.playbackStatus) {
        DeferredCall::callLater([this, busName]() { refreshPlayerPosition(busName, true); });
        auto& timerId = m_positionResyncTimers[busName];
        timerId = TimerManager::instance().start(timerId, k_position_retry_interval,
                                                 [this, busName]() { refreshPlayerPosition(busName, true); });
      }

      if (trackChanged) {
        emitTrackChanged(merged);
      }

      syncSignals(previousActive);
      if (significantChanged && m_changeCallback) {
        m_changeCallback();
      }
    }
  } catch (const sdbus::Error& e) {
    kLog.warn("player query failed name={} err={}", busName, e.what());
    scheduleRecoveryDiscovery();
  }
}

void MprisService::removePlayer(const std::string& busName) {
  const auto previousActive = activePlayer();

  if (!m_players.contains(busName) && !m_playerProxies.contains(busName)) {
    return;
  }

  m_players.erase(busName);
  m_playerProxies.erase(busName);
  m_logicalTrackSignatures.erase(busName);
  m_positionOffsetsUs.erase(busName);
  if (auto it = m_positionResyncTimers.find(busName); it != m_positionResyncTimers.end()) {
    TimerManager::instance().cancel(it->second);
    m_positionResyncTimers.erase(it);
  }
  m_pendingPositionSignalRefresh.erase(busName);
  m_hasAuthoritativePositionSample.erase(busName);
  m_lastLogicalTrackChangeAt.erase(busName);
  m_previousTrackRawPositionUs.erase(busName);
  m_lastSeekCommandAt.erase(busName);
  m_recentNoSignalPauseAt.erase(busName);
  m_pendingPositionCandidateUs.erase(busName);
  m_pendingPositionCandidateMatches.erase(busName);
  m_pendingPositionCandidateAt.erase(busName);
  m_lastPositionSampleAt.erase(busName);
  m_lastPropertiesUpdate.erase(busName);
  m_lastPlayingUpdate.erase(busName);
  m_lastStrongMetadataUpdate.erase(busName);
  if (m_lastActivePlayer == busName) {
    m_lastActivePlayer.clear();
  }
  emitPlayersChanged();
  syncSignals(previousActive);
  if (m_changeCallback) {
    m_changeCallback();
  }

  // Name-owner churn can race with our own cache updates. Re-run discovery
  // on the next loop tick so transient gaps do not leave media UI empty.
  scheduleRecoveryDiscovery();
}

std::optional<std::string> MprisService::chooseActivePlayer() const {
  if (m_pinnedPlayerPreference.has_value()) {
    const auto it = m_players.find(*m_pinnedPlayerPreference);
    if (it != m_players.end() && !isBlacklisted(it->second)) {
      // kLog.debug("choose active player source=pinned name={}", *m_pinnedPlayerPreference);
      return *m_pinnedPlayerPreference;
    }
  }

  std::optional<std::string> mostRecentPlaying;
  std::chrono::steady_clock::time_point mostRecentPlayingAt{};
  for (const auto& [busName, player] : m_players) {
    if (isBlacklisted(player) || player.playbackStatus != "Playing") {
      continue;
    }
    const auto playingIt = m_lastPlayingUpdate.find(busName);
    const auto seenAt =
        playingIt != m_lastPlayingUpdate.end() ? playingIt->second : std::chrono::steady_clock::time_point{};
    if (!mostRecentPlaying.has_value() || seenAt > mostRecentPlayingAt) {
      mostRecentPlaying = busName;
      mostRecentPlayingAt = seenAt;
    }
  }
  if (mostRecentPlaying.has_value()) {
    // kLog.debug("choose active player source=recent_playing name={}", *mostRecentPlaying);
    return mostRecentPlaying;
  }

  for (const auto& busName : m_preferredPlayers) {
    const auto it = m_players.find(busName);
    if (it != m_players.end() && !isBlacklisted(it->second) && it->second.playbackStatus == "Playing") {
      // kLog.debug("choose active player source=preferred_playing name={}", busName);
      return busName;
    }
  }

  for (const auto& busName : m_preferredPlayers) {
    const auto it = m_players.find(busName);
    if (it != m_players.end() && !isBlacklisted(it->second)) {
      // kLog.debug("choose active player source=preferred_any name={}", busName);
      return busName;
    }
  }

  if (!m_lastActivePlayer.empty()) {
    const auto it = m_players.find(m_lastActivePlayer);
    if (it != m_players.end() && !isBlacklisted(it->second)) {
      // kLog.debug("choose active player source=last_active name={}", m_lastActivePlayer);
      return m_lastActivePlayer;
    }
  }

  for (const auto& [busName, player] : m_players) {
    if (!isBlacklisted(player)) {
      // kLog.debug("choose active player source=first_cached name={}", busName);
      return busName;
    }
  }

  // kLog.debug("choose active player source=none");
  return std::nullopt;
}

bool MprisService::isBlacklisted(const MprisPlayerInfo& player) const {
  if (m_blacklist.empty()) {
    return false;
  }

  const std::string busName = normalizeFilterToken(player.busName);
  const std::string identity = normalizeFilterToken(player.identity);
  const std::string desktopEntry = normalizeFilterToken(player.desktopEntry);

  for (const auto& token : m_blacklist) {
    if (token == busName || token == identity || token == desktopEntry) {
      return true;
    }
    if (!token.empty() && busName.find(token) != std::string::npos) {
      return true;
    }
  }

  return false;
}

bool MprisService::callPlayerMethod(const std::string& busName, const char* methodName) {
  const auto it = m_playerProxies.find(busName);
  if (it == m_playerProxies.end()) {
    return false;
  }

  try {
    it->second->callMethod(methodName).onInterface(k_mpris_player_interface);
    addOrRefreshPlayer(busName);
    kLog.debug("control name={} method={}", busName, methodName);
    return true;
  } catch (const sdbus::Error& e) {
    kLog.warn("control failed name={} method={} err={}", busName, methodName, e.what());
    return false;
  }
}

bool MprisService::canInvoke(const MprisPlayerInfo& player, const char* methodName) const {
  const std::string_view method{methodName};
  if (method == "PlayPause") {
    return player.canPlay || player.canPause;
  }
  if (method == "Next") {
    return player.canGoNext;
  }
  if (method == "Previous") {
    return player.canGoPrevious;
  }
  return false;
}

bool MprisService::onPlayPausePlayer(const std::string& busName) {
  if (busName.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  if (!m_players.contains(busName)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }

  const bool ok = playPause(busName);
  if (!ok) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotSupported"},
                       "player does not support PlayPause");
  }
  return true;
}

bool MprisService::onNextPlayer(const std::string& busName) {
  if (busName.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  if (!m_players.contains(busName)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }

  const bool ok = next(busName);
  if (!ok) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotSupported"}, "player does not support Next");
  }
  return true;
}

bool MprisService::onPreviousPlayer(const std::string& busName) {
  if (busName.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  if (!m_players.contains(busName)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }

  const bool ok = previous(busName);
  if (!ok) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotSupported"}, "player does not support Previous");
  }
  return true;
}

bool MprisService::onPlayPauseActive() {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "no active player available");
  }
  return onPlayPausePlayer(*active);
}

bool MprisService::onNextActive() {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "no active player available");
  }
  return onNextPlayer(*active);
}

bool MprisService::onPreviousActive() {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "no active player available");
  }
  return onPreviousPlayer(*active);
}

bool MprisService::onSeekPlayer(const std::string& busName, int64_t offsetUs) {
  if (busName.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  if (!m_players.contains(busName)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }

  if (!seek(busName, offsetUs)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotSupported"}, "player does not support Seek");
  }
  return true;
}

bool MprisService::onSeekActive(int64_t offsetUs) {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "no active player available");
  }
  return onSeekPlayer(*active, offsetUs);
}

bool MprisService::onSetPositionPlayer(const std::string& busName, int64_t positionUs) {
  if (busName.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  if (!m_players.contains(busName)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }

  if (!setPosition(busName, positionUs)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotSupported"},
                       "player does not support SetPosition");
  }
  return true;
}

bool MprisService::onSetPositionActive(int64_t positionUs) {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "no active player available");
  }
  return onSetPositionPlayer(*active, positionUs);
}

int64_t MprisService::onGetPositionPlayer(const std::string& busName) const {
  if (busName.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  const auto pos = position(busName);
  if (!pos.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }
  return *pos;
}

int64_t MprisService::onGetPositionActive() const {
  const auto pos = positionActive();
  if (!pos.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "no active player available");
  }
  return *pos;
}

double MprisService::onGetVolumePlayer(const std::string& busName) const {
  if (busName.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  const auto currentVolume = volume(busName);
  if (!currentVolume.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }
  return *currentVolume;
}

double MprisService::onGetVolumeActive() const {
  const auto currentVolume = volumeActive();
  if (!currentVolume.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "no active player available");
  }
  return *currentVolume;
}

bool MprisService::onSetVolumePlayer(const std::string& busName, double volume) {
  if (busName.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  if (!std::isfinite(volume) || volume < 0.0) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"},
                       "volume must be a finite non-negative number");
  }

  if (!m_players.contains(busName)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }

  if (!setVolume(busName, volume)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotSupported"},
                       "player does not support Volume updates");
  }
  return true;
}

bool MprisService::onSetVolumeActive(double volume) {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "no active player available");
  }
  return onSetVolumePlayer(*active, volume);
}

bool MprisService::onGetShufflePlayer(const std::string& busName) const {
  if (busName.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  const auto currentShuffle = shuffle(busName);
  if (!currentShuffle.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }
  return *currentShuffle;
}

bool MprisService::onGetShuffleActive() const {
  const auto currentShuffle = shuffleActive();
  if (!currentShuffle.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "no active player available");
  }
  return *currentShuffle;
}

bool MprisService::onSetShufflePlayer(const std::string& busName, bool shuffle) {
  if (busName.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  if (!m_players.contains(busName)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }

  if (!setShuffle(busName, shuffle)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotSupported"},
                       "player does not support Shuffle updates");
  }
  return true;
}

bool MprisService::onSetShuffleActive(bool shuffle) {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "no active player available");
  }
  return onSetShufflePlayer(*active, shuffle);
}

std::string MprisService::onGetLoopStatusPlayer(const std::string& busName) const {
  if (busName.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  const auto currentLoopStatus = loopStatus(busName);
  if (!currentLoopStatus.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }
  return *currentLoopStatus;
}

std::string MprisService::onGetLoopStatusActive() const {
  const auto currentLoopStatus = loopStatusActive();
  if (!currentLoopStatus.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "no active player available");
  }
  return *currentLoopStatus;
}

bool MprisService::onSetLoopStatusPlayer(const std::string& busName, const std::string& loopStatus) {
  if (busName.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  if (!is_valid_loop_status(loopStatus)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"},
                       "loop_status must be one of: None, Track, Playlist");
  }

  if (!m_players.contains(busName)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }

  if (!setLoopStatus(busName, loopStatus)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotSupported"},
                       "player does not support LoopStatus updates");
  }
  return true;
}

bool MprisService::onSetLoopStatusActive(const std::string& loopStatus) {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "no active player available");
  }
  return onSetLoopStatusPlayer(*active, loopStatus);
}

bool MprisService::onSetActivePlayerPreference(const std::string& busName) {
  if (busName.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  if (!setPinnedPlayerPreference(busName)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }
  return true;
}

bool MprisService::onClearActivePlayerPreference() {
  clearPinnedPlayerPreference();
  return true;
}

bool MprisService::onSetPreferredPlayers(const std::vector<std::string>& preferredBusNames) {
  setPreferredPlayers(preferredBusNames);
  return true;
}

std::tuple<bool, std::string, std::vector<std::string>> MprisService::onGetPlayerPreferences() const {
  if (!m_pinnedPlayerPreference.has_value()) {
    return {false, "", m_preferredPlayers};
  }
  return {true, *m_pinnedPlayerPreference, m_preferredPlayers};
}

MprisPlayerInfo MprisService::readPlayerInfo(sdbus::IProxy& proxy, const std::string& busName) const {
  std::map<std::string, sdbus::Variant> rootProps;
  std::map<std::string, sdbus::Variant> playerProps;

  try {
    for (auto& [k, v] : proxy.getAllProperties().onInterface(k_mpris_root_interface)) {
      rootProps.emplace(std::string(k), std::move(v));
    }
  } catch (const sdbus::Error&) {
  }
  try {
    for (auto& [k, v] : proxy.getAllProperties().onInterface(k_mpris_player_interface)) {
      playerProps.emplace(std::string(k), std::move(v));
    }
  } catch (const sdbus::Error&) {
  }

  auto metadata = get_variant_map_from_props(playerProps, "Metadata");

  return MprisPlayerInfo{
      .busName = busName,
      .identity = get_string_from_props(rootProps, "Identity"),
      .desktopEntry = get_string_from_props(rootProps, "DesktopEntry"),
      .playbackStatus = get_string_from_props(playerProps, "PlaybackStatus"),
      .trackId = get_object_path_from_variant(metadata, "mpris:trackid"),
      .title = get_string_from_variant(metadata, "xesam:title"),
      .artists = get_string_array_from_variant(metadata, "xesam:artist"),
      .album = get_string_from_variant(metadata, "xesam:album"),
      .sourceUrl = get_string_from_variant(metadata, "xesam:url"),
      .artUrl = get_string_from_variant(metadata, "mpris:artUrl"),
      .loopStatus = get_string_from_props_or(playerProps, "LoopStatus", "None"),
      .shuffle = get_bool_from_props(playerProps, "Shuffle"),
      .volume = get_double_from_props(playerProps, "Volume", 1.0),
      .positionUs = 0,
      .lengthUs = sanitizeLengthUs(get_int64_from_variant(metadata, "mpris:length")),
      .canPlay = get_bool_from_props(playerProps, "CanPlay"),
      .canPause = get_bool_from_props(playerProps, "CanPause"),
      .canGoNext = get_bool_from_props(playerProps, "CanGoNext"),
      .canGoPrevious = get_bool_from_props(playerProps, "CanGoPrevious"),
      .canSeek = get_bool_from_props(playerProps, "CanSeek"),
  };
}
