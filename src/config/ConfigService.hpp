#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

struct WaylandOutput;

struct BarMonitorOverride {
    std::string match;
    std::optional<bool> enabled;
    std::optional<std::uint32_t> height;
    std::optional<float> padding;
    std::optional<float> gap;
    std::optional<std::vector<std::string>> startWidgets;
    std::optional<std::vector<std::string>> centerWidgets;
    std::optional<std::vector<std::string>> endWidgets;
};

struct BarConfig {
    std::string name = "default";
    std::string position = "top";
    bool enabled = true;
    std::uint32_t height = 42;
    float padding = 16.0f;
    float gap = 8.0f;
    std::vector<std::string> startWidgets = {"clock"};
    std::vector<std::string> centerWidgets = {"workspaces"};
    std::vector<std::string> endWidgets = {"clock"};
    std::vector<BarMonitorOverride> monitorOverrides;
};

struct ClockConfig {
    std::string format = "%H:%M";
};

struct Config {
    std::vector<BarConfig> bars;
    ClockConfig clock;
};

class ConfigService {
public:
    ConfigService();

    [[nodiscard]] const Config& config() const noexcept { return m_config; }

    [[nodiscard]] static BarConfig resolveForOutput(const BarConfig& base,
                                                     const WaylandOutput& output);

private:
    void loadFromFile(const std::string& path);

    Config m_config;
};
