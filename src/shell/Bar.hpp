#pragma once

#include "shell/BarInstance.hpp"
#include "wayland/WaylandConnection.hpp"

#include <cstdint>
#include <memory>
#include <vector>

class TimeService;

class Bar {
public:
    Bar();

    bool initialize(TimeService* timeService);
    [[nodiscard]] bool isRunning() const noexcept;
    [[nodiscard]] int displayFd() const noexcept;
    void dispatchPending();
    void dispatchReadable();
    void flush();
    const WaylandConnection& connection() const noexcept;

private:
    void syncInstances();
    void createInstance(const WaylandOutput& output);
    void destroyInstance(std::uint32_t outputName);
    void populateWidgets(BarInstance& instance);
    void buildScene(BarInstance& instance, std::uint32_t width, std::uint32_t height);
    void updateWidgets(BarInstance& instance);

    WaylandConnection m_wayland;
    std::vector<std::unique_ptr<BarInstance>> m_instances;
};
