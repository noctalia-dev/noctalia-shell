#pragma once

#include <cstdint>
#include <functional>
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
    std::string format = "{:%H:%M}";
};

struct Config {
    std::vector<BarConfig> bars;
    ClockConfig clock;
};

class ConfigService {
public:
    using ReloadCallback = std::function<void()>;

    ConfigService();
    ~ConfigService();

    ConfigService(const ConfigService&) = delete;
    ConfigService& operator=(const ConfigService&) = delete;

    [[nodiscard]] const Config& config() const noexcept { return m_config; }
    [[nodiscard]] int watchFd() const noexcept { return m_inotifyFd; }

    void setReloadCallback(ReloadCallback callback);
    void checkReload();

    [[nodiscard]] static BarConfig resolveForOutput(const BarConfig& base,
                                                     const WaylandOutput& output);

private:
    void loadFromFile(const std::string& path);
    void setupWatch();

    Config m_config;
    std::string m_configPath;
    int m_inotifyFd = -1;
    int m_watchFd = -1;
    bool m_pendingReload = false;
    ReloadCallback m_reloadCallback;
};
