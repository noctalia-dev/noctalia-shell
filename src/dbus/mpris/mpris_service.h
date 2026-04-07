#pragma once

#include <chrono>
#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <tuple>
#include <unordered_map>
#include <vector>

namespace sdbus {
class IObject;
class IProxy;
} // namespace sdbus

class SessionBus;

struct MprisPlayerInfo {
  std::string busName;
  std::string identity;
  std::string desktopEntry;
  std::string playbackStatus;
  std::string trackId;
  std::string title;
  std::vector<std::string> artists;
  std::string album;
  std::string sourceUrl;
  std::string artUrl;
  std::string loopStatus{"None"};
  bool shuffle{false};
  double volume{1.0};
  int64_t positionUs{0};
  int64_t lengthUs{0};
  bool canPlay{false};
  bool canPause{false};
  bool canGoNext{false};
  bool canGoPrevious{false};
  bool canSeek{false};

  bool operator==(const MprisPlayerInfo&) const = default;
};

class MprisService {
public:
  explicit MprisService(SessionBus& bus);

  [[nodiscard]] const std::unordered_map<std::string, MprisPlayerInfo>& players() const noexcept;
  [[nodiscard]] std::vector<MprisPlayerInfo> listPlayers() const;
  [[nodiscard]] std::optional<MprisPlayerInfo> activePlayer() const;
  void refreshPlayers();

  bool playPause(const std::string& busName);
  bool next(const std::string& busName);
  bool previous(const std::string& busName);
  bool playPauseActive();
  bool nextActive();
  bool previousActive();
  bool seek(const std::string& busName, int64_t offsetUs);
  bool seekActive(int64_t offsetUs);
  bool setPosition(const std::string& busName, int64_t positionUs);
  bool setPositionActive(int64_t positionUs);
  bool setVolume(const std::string& busName, double volume);
  bool setVolumeActive(double volume);
  bool setShuffle(const std::string& busName, bool shuffle);
  bool setShuffleActive(bool shuffle);
  bool setLoopStatus(const std::string& busName, std::string loopStatus);
  bool setLoopStatusActive(std::string loopStatus);
  [[nodiscard]] std::optional<int64_t> position(const std::string& busName) const;
  [[nodiscard]] std::optional<int64_t> positionActive() const;
  [[nodiscard]] std::optional<double> volume(const std::string& busName) const;
  [[nodiscard]] std::optional<double> volumeActive() const;
  [[nodiscard]] std::optional<bool> shuffle(const std::string& busName) const;
  [[nodiscard]] std::optional<bool> shuffleActive() const;
  [[nodiscard]] std::optional<std::string> loopStatus(const std::string& busName) const;
  [[nodiscard]] std::optional<std::string> loopStatusActive() const;

  bool setPinnedPlayerPreference(const std::string& busName);
  void clearPinnedPlayerPreference();
  void setPreferredPlayers(std::vector<std::string> preferredBusNames);
  void setChangeCallback(std::function<void()> callback);
  [[nodiscard]] std::optional<std::string> pinnedPlayerPreference() const;
  [[nodiscard]] const std::vector<std::string>& preferredPlayers() const noexcept;

private:
  void registerControlApi();
  void emitPlayersChanged();
  void emitActivePlayerChanged();
  void emitTrackChanged(const MprisPlayerInfo& player);
  void syncSignals(const std::optional<MprisPlayerInfo>& previousActive);
  void registerBusSignals();
  void discoverPlayers();
  void scheduleStartupRediscovery();
  void addOrRefreshPlayer(const std::string& busName);
  void removePlayer(const std::string& busName);
  [[nodiscard]] MprisPlayerInfo readPlayerInfo(sdbus::IProxy& proxy, const std::string& busName) const;
  [[nodiscard]] std::optional<std::string> chooseActivePlayer() const;
  [[nodiscard]] bool callPlayerMethod(const std::string& busName, const char* methodName);
  [[nodiscard]] bool canInvoke(const MprisPlayerInfo& player, const char* methodName) const;

  bool onPlayPausePlayer(const std::string& busName);
  bool onNextPlayer(const std::string& busName);
  bool onPreviousPlayer(const std::string& busName);
  bool onPlayPauseActive();
  bool onNextActive();
  bool onPreviousActive();
  bool onSeekPlayer(const std::string& busName, int64_t offsetUs);
  bool onSeekActive(int64_t offsetUs);
  bool onSetPositionPlayer(const std::string& busName, int64_t positionUs);
  bool onSetPositionActive(int64_t positionUs);
  bool onSetVolumePlayer(const std::string& busName, double volume);
  bool onSetVolumeActive(double volume);
  bool onSetShufflePlayer(const std::string& busName, bool shuffle);
  bool onSetShuffleActive(bool shuffle);
  bool onSetLoopStatusPlayer(const std::string& busName, const std::string& loopStatus);
  bool onSetLoopStatusActive(const std::string& loopStatus);
  int64_t onGetPositionPlayer(const std::string& busName) const;
  int64_t onGetPositionActive() const;
  double onGetVolumePlayer(const std::string& busName) const;
  double onGetVolumeActive() const;
  bool onGetShufflePlayer(const std::string& busName) const;
  bool onGetShuffleActive() const;
  std::string onGetLoopStatusPlayer(const std::string& busName) const;
  std::string onGetLoopStatusActive() const;
  bool onSetActivePlayerPreference(const std::string& busName);
  bool onClearActivePlayerPreference();
  bool onSetPreferredPlayers(const std::vector<std::string>& preferredBusNames);
  [[nodiscard]] std::tuple<bool, std::string, std::vector<std::string>> onGetPlayerPreferences() const;

  SessionBus& m_bus;
  std::unique_ptr<sdbus::IObject> m_controlObject;
  std::unique_ptr<sdbus::IProxy> m_dbusProxy;
  std::unordered_map<std::string, std::unique_ptr<sdbus::IProxy>> m_playerProxies;
  std::unordered_map<std::string, MprisPlayerInfo> m_players;
  std::unordered_map<std::string, std::chrono::steady_clock::time_point> m_lastPropertiesUpdate;
  std::unordered_map<std::string, std::chrono::steady_clock::time_point> m_lastPlayingUpdate;
  std::string m_lastActivePlayer;
  std::string m_lastEmittedActivePlayer;
  std::optional<std::string> m_pinnedPlayerPreference;
  std::vector<std::string> m_preferredPlayers;
  std::function<void()> m_changeCallback;
  int m_startupRediscoveryPassesRemaining = 4;
};
