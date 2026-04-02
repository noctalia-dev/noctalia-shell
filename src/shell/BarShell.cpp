#include "shell/BarShell.hpp"

BarShell::BarShell()
    : m_layerSurface(m_connection) {}

bool BarShell::initialize() {
    if (!m_connection.connect()) {
        return false;
    }

    m_layerSurface.initialize();
    return true;
}

void BarShell::run() {
    while (m_layerSurface.isRunning()) {
        m_layerSurface.dispatch();
    }
}

const WaylandConnection& BarShell::connection() const noexcept {
    return m_connection;
}
