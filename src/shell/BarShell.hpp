#pragma once

#include "wayland/LayerSurface.hpp"
#include "wayland/WaylandConnection.hpp"

class BarShell {
public:
    BarShell();

    bool initialize();
    [[nodiscard]] bool isRunning() const noexcept;
    [[nodiscard]] int displayFd() const noexcept;
    void dispatchPending();
    void dispatchReadable();
    void flush();
    void run();
    const WaylandConnection& connection() const noexcept;

private:
    WaylandConnection m_connection;
    LayerSurface m_layerSurface;
};
