#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

namespace sdbus {
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

private:
    void registerBusSignals();
    void discoverPlayers();
    void addOrRefreshPlayer(const std::string& bus_name);
    void removePlayer(const std::string& bus_name);
    [[nodiscard]] MprisPlayerInfo readPlayerInfo(sdbus::IProxy& proxy, const std::string& bus_name) const;

    SessionBus&                                                     m_bus;
    std::unique_ptr<sdbus::IProxy>                                  m_dbus_proxy;
    std::unordered_map<std::string, std::unique_ptr<sdbus::IProxy>> m_player_proxies;
    std::unordered_map<std::string, MprisPlayerInfo>                m_players;
};