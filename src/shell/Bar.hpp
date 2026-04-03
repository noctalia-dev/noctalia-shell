#pragma once

#include "shell/BarInstance.hpp"
#include "ui/WidgetFactory.hpp"

#include <cstdint>
#include <memory>
#include <vector>

class ConfigService;
class TimeService;
class WaylandConnection;

class Bar {
public:
    Bar();

    bool initialize(WaylandConnection& wayland, ConfigService* config, TimeService* timeService);
    void reload();
    void onOutputChange();
    void onWorkspaceChange();
    [[nodiscard]] bool isRunning() const noexcept;

private:
    void syncInstances();
    void createInstance(const WaylandOutput& output, const BarConfig& barConfig);
    void destroyInstance(std::uint32_t outputName);
    void populateWidgets(BarInstance& instance);
    void buildScene(BarInstance& instance, std::uint32_t width, std::uint32_t height);
    void updateWidgets(BarInstance& instance);

    WaylandConnection* m_wayland = nullptr;
    ConfigService* m_config = nullptr;
    TimeService* m_time = nullptr;
    std::unique_ptr<WidgetFactory> m_widgetFactory;
    std::vector<std::unique_ptr<BarInstance>> m_instances;
};
