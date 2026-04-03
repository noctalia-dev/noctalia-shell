#include "dbus/mpris/MprisService.hpp"

#include "core/Log.hpp"
#include "dbus/SessionBus.hpp"

#include <map>
#include <sdbus-c++/IProxy.h>
#include <sdbus-c++/Types.h>
#include <string_view>

namespace {

static constexpr auto k_dbus_interface = "org.freedesktop.DBus";
static constexpr auto k_properties_interface = "org.freedesktop.DBus.Properties";
static constexpr auto k_mpris_root_interface = "org.mpris.MediaPlayer2";
static constexpr auto k_mpris_player_interface = "org.mpris.MediaPlayer2.Player";
static const sdbus::ServiceName k_dbus_name{"org.freedesktop.DBus"};
static const sdbus::ObjectPath k_dbus_path{"/org/freedesktop/DBus"};
static const sdbus::ObjectPath k_mpris_path{"/org/mpris/MediaPlayer2"};

bool is_mpris_bus_name(std::string_view name) {
    return name.starts_with("org.mpris.MediaPlayer2.");
}

template<typename T>
T get_property_or(sdbus::IProxy& proxy, std::string_view interface_name,
                  std::string_view property_name, T fallback) {
    try {
        const sdbus::Variant value = proxy.getProperty(property_name).onInterface(interface_name);
        return value.get<T>();
    } catch (const sdbus::Error&) {
        return fallback;
    }
}

std::map<std::string, sdbus::Variant> get_metadata_or(sdbus::IProxy& proxy) {
    return get_property_or(proxy,
                           k_mpris_player_interface,
                           "Metadata",
                           std::map<std::string, sdbus::Variant>{});
}

std::string get_string_from_variant(const std::map<std::string, sdbus::Variant>& values,
                                    std::string_view key) {
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

std::vector<std::string> get_string_array_from_variant(
    const std::map<std::string, sdbus::Variant>& values,
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

int64_t get_int64_from_variant(const std::map<std::string, sdbus::Variant>& values,
                               std::string_view key) {
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

} // namespace

MprisService::MprisService(SessionBus& bus)
    : m_bus(bus)
    , m_dbus_proxy(sdbus::createProxy(bus.connection(), k_dbus_name, k_dbus_path)) {
    registerBusSignals();
    discoverPlayers();
}

const std::unordered_map<std::string, MprisPlayerInfo>& MprisService::players() const noexcept {
    return m_players;
}

void MprisService::registerBusSignals() {
    m_dbus_proxy->uponSignal("NameOwnerChanged")
        .onInterface(k_dbus_interface)
        .call([this](const std::string& name,
                     const std::string& old_owner,
                     const std::string& new_owner) {
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
    m_dbus_proxy->callMethod("ListNames")
        .onInterface(k_dbus_interface)
        .storeResultsTo(names);

    for (const auto& name : names) {
        if (is_mpris_bus_name(name)) {
            addOrRefreshPlayer(name);
        }
    }
}

void MprisService::addOrRefreshPlayer(const std::string& bus_name) {
    auto [proxy_it, inserted] = m_player_proxies.emplace(
        bus_name,
        sdbus::createProxy(m_bus.connection(), sdbus::ServiceName{bus_name}, k_mpris_path));

    if (inserted) {
        proxy_it->second->uponSignal("PropertiesChanged")
            .onInterface(k_properties_interface)
            .call([this, bus_name](const std::string& interface_name,
                                   const std::map<std::string, sdbus::Variant>&,
                                   const std::vector<std::string>&) {
                if (interface_name == k_mpris_root_interface ||
                    interface_name == k_mpris_player_interface) {
                    addOrRefreshPlayer(bus_name);
                }
            });
    }

    try {
        const MprisPlayerInfo info = readPlayerInfo(*proxy_it->second, bus_name);
        const auto existing = m_players.find(bus_name);
        if (existing == m_players.end()) {
            m_players.emplace(bus_name, info);
            logInfo("mpris added player name={} identity=\"{}\" status={} title=\"{}\" artist=\"{}\"",
                    info.bus_name, info.identity, info.playback_status, info.title, primary_artist(info.artists));
            return;
        }

        if (existing->second != info) {
            existing->second = info;
            logDebug("mpris updated player name={} status={} title=\"{}\" artist=\"{}\"",
                     info.bus_name, info.playback_status, info.title, primary_artist(info.artists));
        }
    } catch (const sdbus::Error& e) {
        logWarn("mpris player query failed name={} err={}", bus_name, e.what());
    }
}

void MprisService::removePlayer(const std::string& bus_name) {
    if (!m_players.contains(bus_name) && !m_player_proxies.contains(bus_name)) {
        return;
    }

    m_players.erase(bus_name);
    m_player_proxies.erase(bus_name);
    logInfo("mpris removed player name={}", bus_name);
}

MprisPlayerInfo MprisService::readPlayerInfo(sdbus::IProxy& proxy, const std::string& bus_name) const {
    const auto metadata = get_metadata_or(proxy);

    return MprisPlayerInfo{
        .bus_name = bus_name,
        .identity = get_property_or(proxy, k_mpris_root_interface, "Identity", std::string{}),
        .desktop_entry = get_property_or(proxy, k_mpris_root_interface, "DesktopEntry", std::string{}),
        .playback_status = get_property_or(proxy, k_mpris_player_interface, "PlaybackStatus", std::string{}),
        .title = get_string_from_variant(metadata, "xesam:title"),
        .artists = get_string_array_from_variant(metadata, "xesam:artist"),
        .album = get_string_from_variant(metadata, "xesam:album"),
        .art_url = get_string_from_variant(metadata, "mpris:artUrl"),
        .length_us = get_int64_from_variant(metadata, "mpris:length"),
        .can_play = get_property_or(proxy, k_mpris_player_interface, "CanPlay", false),
        .can_pause = get_property_or(proxy, k_mpris_player_interface, "CanPause", false),
        .can_go_next = get_property_or(proxy, k_mpris_player_interface, "CanGoNext", false),
        .can_go_previous = get_property_or(proxy, k_mpris_player_interface, "CanGoPrevious", false),
    };
}