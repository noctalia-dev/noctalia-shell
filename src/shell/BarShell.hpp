#pragma once

#include "wayland/LayerSurface.hpp"
#include "wayland/WaylandConnection.hpp"

class BarShell {
public:
    BarShell();

    bool initialize();
    void run();
    const WaylandConnection& connection() const noexcept;

private:
    WaylandConnection m_connection;
    LayerSurface m_layerSurface;
};
