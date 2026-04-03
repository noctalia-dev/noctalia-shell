#pragma once

#include "shell/BarInstance.hpp"
#include "ui/WidgetFactory.hpp"
#include "wayland/WaylandConnection.hpp"

#include <cstdint>
#include <memory>
#include <vector>

class ConfigService;
class TimeService;

class Bar {
public:
    Bar();

    bool initialize(ConfigService* config, TimeService* timeService);
    [[nodiscard]] bool isRunning() const noexcept;
    [[nodiscard]] int displayFd() const noexcept;
    void dispatchPending();
    void dispatchReadable();
    void flush();
    const WaylandConnection& wayland() const noexcept;

private:
    void syncInstances();
    void createInstance(const WaylandOutput& output, const BarConfig& barConfig);
    void destroyInstance(std::uint32_t outputName);
    void populateWidgets(BarInstance& instance);
    void buildScene(BarInstance& instance, std::uint32_t width, std::uint32_t height);
    void updateWidgets(BarInstance& instance);

    WaylandConnection m_wayland;
    ConfigService* m_config = nullptr;
    TimeService* m_time = nullptr;
    std::unique_ptr<WidgetFactory> m_widgetFactory;
    std::vector<std::unique_ptr<BarInstance>> m_instances;
};
