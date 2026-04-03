#include "config/ConfigService.hpp"

#include "core/Log.hpp"
#include "wayland/WaylandConnection.hpp"

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wshadow"
#pragma GCC diagnostic ignored "-Wconversion"
#pragma GCC diagnostic ignored "-Wsign-conversion"
#include <toml.hpp>
#pragma GCC diagnostic pop

#include <cstdlib>
#include <filesystem>

namespace {

std::string configPath() {
    const char* xdg = std::getenv("XDG_CONFIG_HOME");
    if (xdg != nullptr && xdg[0] != '\0') {
        return std::string(xdg) + "/noctalia/config.toml";
    }
    const char* home = std::getenv("HOME");
    if (home != nullptr && home[0] != '\0') {
        return std::string(home) + "/.config/noctalia/config.toml";
    }
    return {};
}

std::vector<std::string> readStringArray(const toml::node& node) {
    std::vector<std::string> result;
    if (auto* arr = node.as_array()) {
        for (const auto& item : *arr) {
            if (auto* str = item.as_string()) {
                result.push_back(str->get());
            }
        }
    }
    return result;
}

bool matchesOutput(const std::string& match, const WaylandOutput& output) {
    // Exact connector name match
    if (!output.connectorName.empty() && match == output.connectorName) {
        return true;
    }
    // Substring match on description
    if (!output.description.empty() && output.description.find(match) != std::string::npos) {
        return true;
    }
    return false;
}

} // namespace

ConfigService::ConfigService() {
    auto path = configPath();
    if (!path.empty() && std::filesystem::exists(path)) {
        loadFromFile(path);
    } else {
        logInfo("config: no config file found, using defaults");
        m_config.bars.push_back(BarConfig{});
    }
}

void ConfigService::loadFromFile(const std::string& path) {
    logInfo("config: loading {}", path);

    toml::table tbl;
    try {
        tbl = toml::parse_file(path);
    } catch (const toml::parse_error& e) {
        logWarn("config: parse error: {}", e.what());
        m_config.bars.push_back(BarConfig{});
        return;
    }

    // Parse [[bar]] array
    if (auto* barArray = tbl["bar"].as_array()) {
        for (const auto& barNode : *barArray) {
            auto* barTbl = barNode.as_table();
            if (barTbl == nullptr) {
                continue;
            }

            BarConfig bar;
            if (auto v = (*barTbl)["name"].value<std::string>()) bar.name = *v;
            if (auto v = (*barTbl)["position"].value<std::string>()) bar.position = *v;
            if (auto v = (*barTbl)["height"].value<int64_t>()) bar.height = static_cast<std::uint32_t>(*v);
            if (auto v = (*barTbl)["padding"].value<double>()) bar.padding = static_cast<float>(*v);
            if (auto v = (*barTbl)["gap"].value<double>()) bar.gap = static_cast<float>(*v);
            if (auto* n = (*barTbl)["start"].as_array()) bar.startWidgets = readStringArray(*n);
            if (auto* n = (*barTbl)["center"].as_array()) bar.centerWidgets = readStringArray(*n);
            if (auto* n = (*barTbl)["end"].as_array()) bar.endWidgets = readStringArray(*n);

            // Parse [[bar.monitor]] overrides
            if (auto* monArray = (*barTbl)["monitor"].as_array()) {
                for (const auto& monNode : *monArray) {
                    auto* monTbl = monNode.as_table();
                    if (monTbl == nullptr) {
                        continue;
                    }

                    BarMonitorOverride ovr;
                    if (auto v = (*monTbl)["match"].value<std::string>()) {
                        ovr.match = *v;
                    } else {
                        continue;  // match is required
                    }

                    if (auto v = (*monTbl)["height"].value<int64_t>()) ovr.height = static_cast<std::uint32_t>(*v);
                    if (auto v = (*monTbl)["padding"].value<double>()) ovr.padding = static_cast<float>(*v);
                    if (auto v = (*monTbl)["gap"].value<double>()) ovr.gap = static_cast<float>(*v);
                    if (auto* n = (*monTbl)["start"].as_array()) ovr.startWidgets = readStringArray(*n);
                    if (auto* n = (*monTbl)["center"].as_array()) ovr.centerWidgets = readStringArray(*n);
                    if (auto* n = (*monTbl)["end"].as_array()) ovr.endWidgets = readStringArray(*n);

                    bar.monitorOverrides.push_back(std::move(ovr));
                }
            }

            m_config.bars.push_back(std::move(bar));
        }
    }

    // Parse [clock]
    if (auto* clockTbl = tbl["clock"].as_table()) {
        if (auto v = (*clockTbl)["format"].value<std::string>()) {
            m_config.clock.format = *v;
        }
    }

    if (m_config.bars.empty()) {
        logInfo("config: no [[bar]] defined, using defaults");
        m_config.bars.push_back(BarConfig{});
    }

    logInfo("config: {} bar(s) defined", m_config.bars.size());
}

BarConfig ConfigService::resolveForOutput(const BarConfig& base, const WaylandOutput& output) {
    BarConfig resolved = base;

    for (const auto& ovr : base.monitorOverrides) {
        if (!matchesOutput(ovr.match, output)) {
            continue;
        }

        logDebug("config: monitor override \"{}\" matched output {} ({})",
                 ovr.match, output.connectorName, output.description);

        if (ovr.height) resolved.height = *ovr.height;
        if (ovr.padding) resolved.padding = *ovr.padding;
        if (ovr.gap) resolved.gap = *ovr.gap;
        if (ovr.startWidgets) resolved.startWidgets = *ovr.startWidgets;
        if (ovr.centerWidgets) resolved.centerWidgets = *ovr.centerWidgets;
        if (ovr.endWidgets) resolved.endWidgets = *ovr.endWidgets;
        break;  // first match wins
    }

    return resolved;
}
