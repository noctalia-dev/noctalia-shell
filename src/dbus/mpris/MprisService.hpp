#pragma once

#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

namespace sdbus {
class IObject;
class IProxy;
}

class SessionBus;

struct MprisPlayerInfo {
    std::string              bus_name;
    std::string              identity;
    std::string              desktop_entry;
    std::string              playback_status;
    std::string              title;
    std::vector<std::string> artists;
    std::string              album;
    std::string              art_url;
    int64_t                  length_us{0};
    bool                     can_play{false};
    bool                     can_pause{false};
    bool                     can_go_next{false};
    bool                     can_go_previous{false};

    bool operator==(const MprisPlayerInfo&) const = default;
};

class MprisService {
public:
    explicit MprisService(SessionBus& bus);

    [[nodiscard]] const std::unordered_map<std::string, MprisPlayerInfo>& players() const noexcept;
    [[nodiscard]] std::vector<MprisPlayerInfo> listPlayers() const;
    [[nodiscard]] std::optional<MprisPlayerInfo> activePlayer() const;

    bool playPause(const std::string& bus_name);
    bool next(const std::string& bus_name);
    bool previous(const std::string& bus_name);
    bool playPauseActive();
    bool nextActive();
    bool previousActive();

private:
    void registerControlApi();
    void registerBusSignals();
    void discoverPlayers();
    void addOrRefreshPlayer(const std::string& bus_name);
    void removePlayer(const std::string& bus_name);
    [[nodiscard]] MprisPlayerInfo readPlayerInfo(sdbus::IProxy& proxy, const std::string& bus_name) const;
    [[nodiscard]] std::optional<std::string> chooseActivePlayer() const;
    [[nodiscard]] bool callPlayerMethod(const std::string& bus_name, const char* method_name);
    [[nodiscard]] bool canInvoke(const MprisPlayerInfo& player, const char* method_name) const;

    bool onPlayPausePlayer(const std::string& bus_name);
    bool onNextPlayer(const std::string& bus_name);
    bool onPreviousPlayer(const std::string& bus_name);
    bool onPlayPauseActive();
    bool onNextActive();
    bool onPreviousActive();

    SessionBus&                                                     m_bus;
    std::unique_ptr<sdbus::IObject>                                 m_control_object;
    std::unique_ptr<sdbus::IProxy>                                  m_dbus_proxy;
    std::unordered_map<std::string, std::unique_ptr<sdbus::IProxy>> m_player_proxies;
    std::unordered_map<std::string, MprisPlayerInfo>                m_players;
    std::string                                                      m_last_active_player;
};