#include "shell/BarShell.hpp"

#include <stdexcept>

#include <wayland-client-core.h>

BarShell::BarShell()
    : m_layerSurface(m_connection) {}

bool BarShell::initialize() {
    if (!m_connection.connect()) {
        return false;
    }

    m_layerSurface.initialize();
    return true;
}

bool BarShell::isRunning() const noexcept {
    return m_layerSurface.isRunning();
}

int BarShell::displayFd() const noexcept {
    if (!m_connection.isConnected()) {
        return -1;
    }

    return wl_display_get_fd(m_connection.display());
}

void BarShell::dispatchPending() {
    if (!m_connection.isConnected()) {
        return;
    }

    if (wl_display_dispatch_pending(m_connection.display()) < 0) {
        throw std::runtime_error("failed to dispatch pending Wayland events");
    }
}

void BarShell::dispatchReadable() {
    if (!m_connection.isConnected()) {
        return;
    }

    if (wl_display_dispatch(m_connection.display()) < 0) {
        throw std::runtime_error("failed to dispatch Wayland events");
    }
}

void BarShell::flush() {
    if (!m_connection.isConnected()) {
        return;
    }

    if (wl_display_flush(m_connection.display()) < 0) {
        throw std::runtime_error("failed to flush Wayland display");
    }
}

void BarShell::run() {
    while (m_layerSurface.isRunning()) {
        m_layerSurface.dispatch();
    }
}

const WaylandConnection& BarShell::connection() const noexcept {
    return m_connection;
}
