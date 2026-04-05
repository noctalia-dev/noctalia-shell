#include "dbus/mpris/mpris_service.h"

#include "core/log.h"
#include "dbus/session_bus.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <map>
#include <sdbus-c++/IObject.h>
#include <sdbus-c++/IProxy.h>
#include <sdbus-c++/Types.h>
#include <string_view>
#include <tuple>
#include <unordered_set>

namespace {

static constexpr auto k_dbus_interface = "org.freedesktop.DBus";
static constexpr auto k_properties_interface = "org.freedesktop.DBus.Properties";
static constexpr auto k_mpris_root_interface = "org.mpris.MediaPlayer2";
static constexpr auto k_mpris_player_interface = "org.mpris.MediaPlayer2.Player";
static constexpr auto k_noctalia_mpris_interface = "dev.noctalia.Mpris";
static constexpr auto k_properties_debounce_window = std::chrono::milliseconds{120};
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
    return {};
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
    return 0;
  }
}

std::string primary_artist(const std::vector<std::string>& artists) {
  if (artists.empty()) {
    return {};
  }
  return artists.front();
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

} // namespace

MprisService::MprisService(SessionBus& bus)
    : m_bus(bus), m_dbusProxy(sdbus::createProxy(bus.connection(), k_dbus_name, k_dbus_path)) {
  registerControlApi();
  registerBusSignals();
  discoverPlayers();
}

const std::unordered_map<std::string, MprisPlayerInfo>& MprisService::players() const noexcept { return m_players; }

std::vector<MprisPlayerInfo> MprisService::listPlayers() const {
  std::vector<MprisPlayerInfo> result;
  result.reserve(m_players.size());
  for (const auto& [_, player] : m_players) {
    result.push_back(player);
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
  return it->second;
}

bool MprisService::playPause(const std::string& bus_name) {
  const auto it = m_players.find(bus_name);
  if (it == m_players.end()) {
    return false;
  }
  if (!canInvoke(it->second, "PlayPause")) {
    return false;
  }
  return callPlayerMethod(bus_name, "PlayPause");
}

bool MprisService::next(const std::string& bus_name) {
  const auto it = m_players.find(bus_name);
  if (it == m_players.end()) {
    return false;
  }
  if (!canInvoke(it->second, "Next")) {
    return false;
  }
  return callPlayerMethod(bus_name, "Next");
}

bool MprisService::previous(const std::string& bus_name) {
  const auto it = m_players.find(bus_name);
  if (it == m_players.end()) {
    return false;
  }
  if (!canInvoke(it->second, "Previous")) {
    return false;
  }
  return callPlayerMethod(bus_name, "Previous");
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

bool MprisService::seek(const std::string& bus_name, int64_t offset_us) {
  const auto it = m_players.find(bus_name);
  if (it == m_players.end() || !it->second.canSeek) {
    return false;
  }

  const auto proxy_it = m_playerProxies.find(bus_name);
  if (proxy_it == m_playerProxies.end()) {
    return false;
  }

  try {
    proxy_it->second->callMethod("Seek").onInterface(k_mpris_player_interface).withArguments(offset_us);
    addOrRefreshPlayer(bus_name);
    return true;
  } catch (const sdbus::Error& e) {
    logWarn("mpris seek failed name={} err={}", bus_name, e.what());
    return false;
  }
}

bool MprisService::seekActive(int64_t offset_us) {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    return false;
  }
  return seek(*active, offset_us);
}

bool MprisService::setPosition(const std::string& bus_name, int64_t position_us) {
  const auto it = m_players.find(bus_name);
  if (it == m_players.end() || !it->second.canSeek) {
    return false;
  }

  const auto proxy_it = m_playerProxies.find(bus_name);
  if (proxy_it == m_playerProxies.end()) {
    return false;
  }

  auto fallback_seek = [&]() {
    int64_t current_position_us = it->second.positionUs;
    try {
      const sdbus::Variant position_value =
          proxy_it->second->getProperty("Position").onInterface(k_mpris_player_interface);
      current_position_us = position_value.get<int64_t>();
    } catch (const sdbus::Error& e) {
      logWarn("mpris position refresh failed name={} err={}, using cached value", bus_name, e.what());
    }

    const int64_t offset_us = position_us - current_position_us;
    if (offset_us == 0) {
      return true;
    }
    return seek(bus_name, offset_us);
  };

  if (it->second.trackId.empty()) {
    // Some players don't expose track_id consistently; emulate absolute position with Seek.
    return fallback_seek();
  }

  try {
    proxy_it->second->callMethod("SetPosition")
        .onInterface(k_mpris_player_interface)
        .withArguments(sdbus::ObjectPath{it->second.trackId}, position_us);
    addOrRefreshPlayer(bus_name);
    return true;
  } catch (const sdbus::Error& e) {
    logWarn("mpris set-position failed name={} err={}, falling back to Seek", bus_name, e.what());
    return fallback_seek();
  }
}

bool MprisService::setPositionActive(int64_t position_us) {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    return false;
  }
  return setPosition(*active, position_us);
}

bool MprisService::setVolume(const std::string& bus_name, double volume) {
  const auto it = m_players.find(bus_name);
  if (it == m_players.end()) {
    return false;
  }

  const auto proxy_it = m_playerProxies.find(bus_name);
  if (proxy_it == m_playerProxies.end()) {
    return false;
  }

  try {
    proxy_it->second->setProperty("Volume").onInterface(k_mpris_player_interface).toValue(volume);
    addOrRefreshPlayer(bus_name);
    return true;
  } catch (const sdbus::Error& e) {
    logWarn("mpris set-volume failed name={} err={}", bus_name, e.what());
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

bool MprisService::setShuffle(const std::string& bus_name, bool shuffle) {
  const auto it = m_players.find(bus_name);
  if (it == m_players.end()) {
    return false;
  }

  const auto proxy_it = m_playerProxies.find(bus_name);
  if (proxy_it == m_playerProxies.end()) {
    return false;
  }

  try {
    proxy_it->second->setProperty("Shuffle").onInterface(k_mpris_player_interface).toValue(shuffle);
    addOrRefreshPlayer(bus_name);
    return true;
  } catch (const sdbus::Error& e) {
    logWarn("mpris set-shuffle failed name={} err={}", bus_name, e.what());
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

bool MprisService::setLoopStatus(const std::string& bus_name, std::string loop_status) {
  const auto it = m_players.find(bus_name);
  if (it == m_players.end()) {
    return false;
  }

  const auto proxy_it = m_playerProxies.find(bus_name);
  if (proxy_it == m_playerProxies.end()) {
    return false;
  }

  try {
    proxy_it->second->setProperty("LoopStatus").onInterface(k_mpris_player_interface).toValue(std::move(loop_status));
    addOrRefreshPlayer(bus_name);
    return true;
  } catch (const sdbus::Error& e) {
    logWarn("mpris set-loop-status failed name={} err={}", bus_name, e.what());
    return false;
  }
}

bool MprisService::setLoopStatusActive(std::string loop_status) {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    return false;
  }
  return setLoopStatus(*active, std::move(loop_status));
}

std::optional<int64_t> MprisService::position(const std::string& bus_name) const {
  const auto it = m_players.find(bus_name);
  if (it == m_players.end()) {
    return std::nullopt;
  }
  return it->second.positionUs;
}

std::optional<int64_t> MprisService::positionActive() const {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    return std::nullopt;
  }
  return position(*active);
}

std::optional<double> MprisService::volume(const std::string& bus_name) const {
  const auto it = m_players.find(bus_name);
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

std::optional<bool> MprisService::shuffle(const std::string& bus_name) const {
  const auto it = m_players.find(bus_name);
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

std::optional<std::string> MprisService::loopStatus(const std::string& bus_name) const {
  const auto it = m_players.find(bus_name);
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

bool MprisService::setPinnedPlayerPreference(const std::string& bus_name) {
  if (!m_players.contains(bus_name)) {
    return false;
  }

  const auto previous_active = activePlayer();
  m_pinnedPlayerPreference = bus_name;
  syncSignals(previous_active);
  return true;
}

void MprisService::clearPinnedPlayerPreference() {
  const auto previous_active = activePlayer();
  m_pinnedPlayerPreference.reset();
  syncSignals(previous_active);
}

void MprisService::setPreferredPlayers(std::vector<std::string> preferred_bus_names) {
  std::unordered_set<std::string> seen;
  std::vector<std::string> normalized;
  normalized.reserve(preferred_bus_names.size());

  for (auto& bus_name : preferred_bus_names) {
    if (bus_name.empty()) {
      continue;
    }
    if (seen.insert(bus_name).second) {
      normalized.push_back(std::move(bus_name));
    }
  }

  const auto previous_active = activePlayer();
  m_preferredPlayers = std::move(normalized);
  syncSignals(previous_active);
}

std::optional<std::string> MprisService::pinnedPlayerPreference() const { return m_pinnedPlayerPreference; }

const std::vector<std::string>& MprisService::preferredPlayers() const noexcept { return m_preferredPlayers; }

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
              .implementedAs([this](const std::string& bus_name) { return onSetActivePlayerPreference(bus_name); }),

          sdbus::registerMethod("ClearActivePlayerPreference").withOutputParamNames("success").implementedAs([this]() {
            return onClearActivePlayerPreference();
          }),

          sdbus::registerMethod("SetPreferredPlayers")
              .withInputParamNames("preferred_bus_names")
              .withOutputParamNames("success")
              .implementedAs([this](const std::vector<std::string>& preferred_bus_names) {
                return onSetPreferredPlayers(preferred_bus_names);
              }),

          sdbus::registerMethod("GetPlayerPreferences")
              .withOutputParamNames("has_pinned", "pinned_bus_name", "preferred_bus_names")
              .implementedAs([this]() { return onGetPlayerPreferences(); }),

          sdbus::registerMethod("GetPositionPlayer")
              .withInputParamNames("player_bus_name")
              .withOutputParamNames("position_us")
              .implementedAs([this](const std::string& bus_name) { return onGetPositionPlayer(bus_name); }),

          sdbus::registerMethod("GetPositionActive").withOutputParamNames("position_us").implementedAs([this]() {
            return onGetPositionActive();
          }),

          sdbus::registerMethod("GetVolumePlayer")
              .withInputParamNames("player_bus_name")
              .withOutputParamNames("volume")
              .implementedAs([this](const std::string& bus_name) { return onGetVolumePlayer(bus_name); }),

          sdbus::registerMethod("GetVolumeActive").withOutputParamNames("volume").implementedAs([this]() {
            return onGetVolumeActive();
          }),

          sdbus::registerMethod("SetVolumePlayer")
              .withInputParamNames("player_bus_name", "volume")
              .withOutputParamNames("success")
              .implementedAs(
                  [this](const std::string& bus_name, double volume) { return onSetVolumePlayer(bus_name, volume); }),

          sdbus::registerMethod("SetVolumeActive")
              .withInputParamNames("volume")
              .withOutputParamNames("success")
              .implementedAs([this](double volume) { return onSetVolumeActive(volume); }),

          sdbus::registerMethod("GetShufflePlayer")
              .withInputParamNames("player_bus_name")
              .withOutputParamNames("shuffle")
              .implementedAs([this](const std::string& bus_name) { return onGetShufflePlayer(bus_name); }),

          sdbus::registerMethod("GetShuffleActive").withOutputParamNames("shuffle").implementedAs([this]() {
            return onGetShuffleActive();
          }),

          sdbus::registerMethod("SetShufflePlayer")
              .withInputParamNames("player_bus_name", "shuffle")
              .withOutputParamNames("success")
              .implementedAs(
                  [this](const std::string& bus_name, bool shuffle) { return onSetShufflePlayer(bus_name, shuffle); }),

          sdbus::registerMethod("SetShuffleActive")
              .withInputParamNames("shuffle")
              .withOutputParamNames("success")
              .implementedAs([this](bool shuffle) { return onSetShuffleActive(shuffle); }),

          sdbus::registerMethod("GetLoopStatusPlayer")
              .withInputParamNames("player_bus_name")
              .withOutputParamNames("loop_status")
              .implementedAs([this](const std::string& bus_name) { return onGetLoopStatusPlayer(bus_name); }),

          sdbus::registerMethod("GetLoopStatusActive").withOutputParamNames("loop_status").implementedAs([this]() {
            return onGetLoopStatusActive();
          }),

          sdbus::registerMethod("SetLoopStatusPlayer")
              .withInputParamNames("player_bus_name", "loop_status")
              .withOutputParamNames("success")
              .implementedAs([this](const std::string& bus_name, const std::string& loop_status) {
                return onSetLoopStatusPlayer(bus_name, loop_status);
              }),

          sdbus::registerMethod("SetLoopStatusActive")
              .withInputParamNames("loop_status")
              .withOutputParamNames("success")
              .implementedAs([this](const std::string& loop_status) { return onSetLoopStatusActive(loop_status); }),

          sdbus::registerMethod("SeekPlayer")
              .withInputParamNames("player_bus_name", "offset_us")
              .withOutputParamNames("success")
              .implementedAs(
                  [this](const std::string& bus_name, int64_t offset_us) { return onSeekPlayer(bus_name, offset_us); }),

          sdbus::registerMethod("SeekActive")
              .withInputParamNames("offset_us")
              .withOutputParamNames("success")
              .implementedAs([this](int64_t offset_us) { return onSeekActive(offset_us); }),

          sdbus::registerMethod("SetPositionPlayer")
              .withInputParamNames("player_bus_name", "position_us")
              .withOutputParamNames("success")
              .implementedAs([this](const std::string& bus_name, int64_t position_us) {
                return onSetPositionPlayer(bus_name, position_us);
              }),

          sdbus::registerMethod("SetPositionActive")
              .withInputParamNames("position_us")
              .withOutputParamNames("success")
              .implementedAs([this](int64_t position_us) { return onSetPositionActive(position_us); }),

          sdbus::registerMethod("PlayPausePlayer")
              .withInputParamNames("player_bus_name")
              .withOutputParamNames("success")
              .implementedAs([this](const std::string& bus_name) { return onPlayPausePlayer(bus_name); }),

          sdbus::registerMethod("NextPlayer")
              .withInputParamNames("player_bus_name")
              .withOutputParamNames("success")
              .implementedAs([this](const std::string& bus_name) { return onNextPlayer(bus_name); }),

          sdbus::registerMethod("PreviousPlayer")
              .withInputParamNames("player_bus_name")
              .withOutputParamNames("success")
              .implementedAs([this](const std::string& bus_name) { return onPreviousPlayer(bus_name); }),

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

void MprisService::syncSignals(const std::optional<MprisPlayerInfo>& previous_active) {
  const auto current_active = activePlayer();
  const std::string current_active_name = current_active.has_value() ? current_active->busName : std::string{};

  if (current_active_name != m_lastEmittedActivePlayer) {
    emitActivePlayerChanged();
    m_lastEmittedActivePlayer = current_active_name;
  }

  if (previous_active.has_value() && current_active.has_value() &&
      previous_active->busName == current_active->busName && previous_active->title != current_active->title) {
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
  m_dbusProxy->callMethod("ListNames").onInterface(k_dbus_interface).storeResultsTo(names);

  for (const auto& name : names) {
    if (is_mpris_bus_name(name)) {
      addOrRefreshPlayer(name);
    }
  }
}

void MprisService::addOrRefreshPlayer(const std::string& bus_name) {
  const auto previous_active = activePlayer();

  auto [proxy_it, inserted] = m_playerProxies.emplace(
      bus_name, sdbus::createProxy(m_bus.connection(), sdbus::ServiceName{bus_name}, k_mpris_path));

  if (inserted) {
    proxy_it->second->uponSignal("PropertiesChanged")
        .onInterface(k_properties_interface)
        .call([this, bus_name](const std::string& interface_name, const std::map<std::string, sdbus::Variant>&,
                               const std::vector<std::string>&) {
          if (interface_name == k_mpris_root_interface || interface_name == k_mpris_player_interface) {
            const auto now = std::chrono::steady_clock::now();
            const auto last_it = m_lastPropertiesUpdate.find(bus_name);
            if (last_it != m_lastPropertiesUpdate.end() && now - last_it->second < k_properties_debounce_window) {
              return;
            }
            m_lastPropertiesUpdate[bus_name] = now;
            addOrRefreshPlayer(bus_name);
          }
        });
  }

  try {
    const MprisPlayerInfo info = readPlayerInfo(*proxy_it->second, bus_name);
    if (info.playbackStatus == "Playing" || info.playbackStatus == "Paused") {
      m_lastActivePlayer = bus_name;
    }

    const auto existing = m_players.find(bus_name);
    if (existing == m_players.end()) {
      m_players.emplace(bus_name, info);
      logInfo("mpris added player name={} identity=\"{}\" status={} title=\"{}\" artist=\"{}\" art_url=\"{}\"",
              info.busName, info.identity, info.playbackStatus, info.title, primary_artist(info.artists),
              info.artUrl);
      emitPlayersChanged();
      syncSignals(previous_active);
      return;
    }

    if (existing->second != info) {
      const MprisPlayerInfo previous_info = existing->second;

      // Some players publish metadata and art_url in separate updates.
      // Keep last non-empty art_url until a new non-empty value arrives
      // to avoid transient empty artwork bursts during track switches.
      MprisPlayerInfo merged = info;
      if (merged.artUrl.empty() && !previous_info.artUrl.empty()) {
        merged.artUrl = previous_info.artUrl;
      }

      existing->second = merged;
      logDebug("mpris updated player name={} status={} title=\"{}\" artist=\"{}\" art_url=\"{}\"", merged.busName,
               merged.playbackStatus, merged.title, primary_artist(merged.artists), merged.artUrl);

      if (previous_info.title != merged.title || previous_info.album != merged.album ||
          previous_info.artists != merged.artists || previous_info.artUrl != merged.artUrl ||
          previous_info.trackId != merged.trackId || previous_info.positionUs != merged.positionUs ||
          previous_info.lengthUs != merged.lengthUs) {
        emitTrackChanged(merged);
      }

      syncSignals(previous_active);
    }
  } catch (const sdbus::Error& e) {
    logWarn("mpris player query failed name={} err={}", bus_name, e.what());
  }
}

void MprisService::removePlayer(const std::string& bus_name) {
  const auto previous_active = activePlayer();

  if (!m_players.contains(bus_name) && !m_playerProxies.contains(bus_name)) {
    return;
  }

  m_players.erase(bus_name);
  m_playerProxies.erase(bus_name);
  m_lastPropertiesUpdate.erase(bus_name);
  if (m_lastActivePlayer == bus_name) {
    m_lastActivePlayer.clear();
  }
  logInfo("mpris removed player name={}", bus_name);

  emitPlayersChanged();
  syncSignals(previous_active);
}

std::optional<std::string> MprisService::chooseActivePlayer() const {
  if (m_pinnedPlayerPreference.has_value() && m_players.contains(*m_pinnedPlayerPreference)) {
    return *m_pinnedPlayerPreference;
  }

  for (const auto& bus_name : m_preferredPlayers) {
    const auto it = m_players.find(bus_name);
    if (it != m_players.end() && it->second.playbackStatus == "Playing") {
      return bus_name;
    }
  }

  for (const auto& [bus_name, player] : m_players) {
    if (player.playbackStatus == "Playing") {
      return bus_name;
    }
  }

  for (const auto& bus_name : m_preferredPlayers) {
    if (m_players.contains(bus_name)) {
      return bus_name;
    }
  }

  if (!m_lastActivePlayer.empty() && m_players.contains(m_lastActivePlayer)) {
    return m_lastActivePlayer;
  }

  if (!m_players.empty()) {
    return m_players.begin()->first;
  }

  return std::nullopt;
}

bool MprisService::callPlayerMethod(const std::string& bus_name, const char* method_name) {
  const auto it = m_playerProxies.find(bus_name);
  if (it == m_playerProxies.end()) {
    return false;
  }

  try {
    it->second->callMethod(method_name).onInterface(k_mpris_player_interface);
    addOrRefreshPlayer(bus_name);
    logDebug("mpris control name={} method={}", bus_name, method_name);
    return true;
  } catch (const sdbus::Error& e) {
    logWarn("mpris control failed name={} method={} err={}", bus_name, method_name, e.what());
    return false;
  }
}

bool MprisService::canInvoke(const MprisPlayerInfo& player, const char* method_name) const {
  const std::string_view method{method_name};
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

bool MprisService::onPlayPausePlayer(const std::string& bus_name) {
  if (bus_name.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  if (!m_players.contains(bus_name)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }

  const bool ok = playPause(bus_name);
  if (!ok) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotSupported"},
                       "player does not support PlayPause");
  }
  return true;
}

bool MprisService::onNextPlayer(const std::string& bus_name) {
  if (bus_name.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  if (!m_players.contains(bus_name)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }

  const bool ok = next(bus_name);
  if (!ok) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotSupported"}, "player does not support Next");
  }
  return true;
}

bool MprisService::onPreviousPlayer(const std::string& bus_name) {
  if (bus_name.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  if (!m_players.contains(bus_name)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }

  const bool ok = previous(bus_name);
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

bool MprisService::onSeekPlayer(const std::string& bus_name, int64_t offset_us) {
  if (bus_name.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  if (!m_players.contains(bus_name)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }

  if (!seek(bus_name, offset_us)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotSupported"}, "player does not support Seek");
  }
  return true;
}

bool MprisService::onSeekActive(int64_t offset_us) {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "no active player available");
  }
  return onSeekPlayer(*active, offset_us);
}

bool MprisService::onSetPositionPlayer(const std::string& bus_name, int64_t position_us) {
  if (bus_name.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  if (!m_players.contains(bus_name)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }

  if (!setPosition(bus_name, position_us)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotSupported"},
                       "player does not support SetPosition");
  }
  return true;
}

bool MprisService::onSetPositionActive(int64_t position_us) {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "no active player available");
  }
  return onSetPositionPlayer(*active, position_us);
}

int64_t MprisService::onGetPositionPlayer(const std::string& bus_name) const {
  if (bus_name.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  const auto pos = position(bus_name);
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

double MprisService::onGetVolumePlayer(const std::string& bus_name) const {
  if (bus_name.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  const auto current_volume = volume(bus_name);
  if (!current_volume.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }
  return *current_volume;
}

double MprisService::onGetVolumeActive() const {
  const auto current_volume = volumeActive();
  if (!current_volume.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "no active player available");
  }
  return *current_volume;
}

bool MprisService::onSetVolumePlayer(const std::string& bus_name, double volume) {
  if (bus_name.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  if (!std::isfinite(volume) || volume < 0.0) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"},
                       "volume must be a finite non-negative number");
  }

  if (!m_players.contains(bus_name)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }

  if (!setVolume(bus_name, volume)) {
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

bool MprisService::onGetShufflePlayer(const std::string& bus_name) const {
  if (bus_name.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  const auto current_shuffle = shuffle(bus_name);
  if (!current_shuffle.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }
  return *current_shuffle;
}

bool MprisService::onGetShuffleActive() const {
  const auto current_shuffle = shuffleActive();
  if (!current_shuffle.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "no active player available");
  }
  return *current_shuffle;
}

bool MprisService::onSetShufflePlayer(const std::string& bus_name, bool shuffle) {
  if (bus_name.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  if (!m_players.contains(bus_name)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }

  if (!setShuffle(bus_name, shuffle)) {
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

std::string MprisService::onGetLoopStatusPlayer(const std::string& bus_name) const {
  if (bus_name.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  const auto current_loop_status = loopStatus(bus_name);
  if (!current_loop_status.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }
  return *current_loop_status;
}

std::string MprisService::onGetLoopStatusActive() const {
  const auto current_loop_status = loopStatusActive();
  if (!current_loop_status.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "no active player available");
  }
  return *current_loop_status;
}

bool MprisService::onSetLoopStatusPlayer(const std::string& bus_name, const std::string& loop_status) {
  if (bus_name.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  if (!is_valid_loop_status(loop_status)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"},
                       "loop_status must be one of: None, Track, Playlist");
  }

  if (!m_players.contains(bus_name)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }

  if (!setLoopStatus(bus_name, loop_status)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotSupported"},
                       "player does not support LoopStatus updates");
  }
  return true;
}

bool MprisService::onSetLoopStatusActive(const std::string& loop_status) {
  const auto active = chooseActivePlayer();
  if (!active.has_value()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "no active player available");
  }
  return onSetLoopStatusPlayer(*active, loop_status);
}

bool MprisService::onSetActivePlayerPreference(const std::string& bus_name) {
  if (bus_name.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.InvalidArgs"}, "player_bus_name must not be empty");
  }

  if (!setPinnedPlayerPreference(bus_name)) {
    throw sdbus::Error(sdbus::Error::Name{"dev.noctalia.Mpris.Error.NotFound"}, "player was not found");
  }
  return true;
}

bool MprisService::onClearActivePlayerPreference() {
  clearPinnedPlayerPreference();
  return true;
}

bool MprisService::onSetPreferredPlayers(const std::vector<std::string>& preferred_bus_names) {
  setPreferredPlayers(preferred_bus_names);
  return true;
}

std::tuple<bool, std::string, std::vector<std::string>> MprisService::onGetPlayerPreferences() const {
  if (!m_pinnedPlayerPreference.has_value()) {
    return {false, "", m_preferredPlayers};
  }
  return {true, *m_pinnedPlayerPreference, m_preferredPlayers};
}

MprisPlayerInfo MprisService::readPlayerInfo(sdbus::IProxy& proxy, const std::string& bus_name) const {
  const auto metadata = get_metadata_or(proxy);

  return MprisPlayerInfo{
      .busName = bus_name,
      .identity = get_property_or(proxy, k_mpris_root_interface, "Identity", std::string{}),
      .desktopEntry = get_property_or(proxy, k_mpris_root_interface, "DesktopEntry", std::string{}),
      .playbackStatus = get_property_or(proxy, k_mpris_player_interface, "PlaybackStatus", std::string{}),
      .trackId = get_object_path_from_variant(metadata, "mpris:trackid"),
      .title = get_string_from_variant(metadata, "xesam:title"),
      .artists = get_string_array_from_variant(metadata, "xesam:artist"),
      .album = get_string_from_variant(metadata, "xesam:album"),
      .artUrl = get_string_from_variant(metadata, "mpris:artUrl"),
      .loopStatus = get_property_or(proxy, k_mpris_player_interface, "LoopStatus", std::string{"None"}),
      .shuffle = get_property_or(proxy, k_mpris_player_interface, "Shuffle", false),
      .volume = get_property_or(proxy, k_mpris_player_interface, "Volume", 1.0),
      .positionUs = get_property_or(proxy, k_mpris_player_interface, "Position", int64_t{0}),
      .lengthUs = get_int64_from_variant(metadata, "mpris:length"),
      .canPlay = get_property_or(proxy, k_mpris_player_interface, "CanPlay", false),
      .canPause = get_property_or(proxy, k_mpris_player_interface, "CanPause", false),
      .canGoNext = get_property_or(proxy, k_mpris_player_interface, "CanGoNext", false),
      .canGoPrevious = get_property_or(proxy, k_mpris_player_interface, "CanGoPrevious", false),
      .canSeek = get_property_or(proxy, k_mpris_player_interface, "CanSeek", false),
  };
}