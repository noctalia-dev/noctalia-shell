#pragma once

#include "shell/BarInstance.hpp"
#include "wayland/WaylandConnection.hpp"

#include <cstdint>
#include <memory>
#include <vector>

class Bar {
public:
    Bar();

    bool initialize();
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
    void buildScene(BarInstance& instance, std::uint32_t width, std::uint32_t height);

    WaylandConnection m_connection;
    std::vector<std::unique_ptr<BarInstance>> m_instances;
};
