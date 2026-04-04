#include "app/MainLoop.hpp"

#include "app/Application.hpp"
#include "app/PollSource.hpp"
#include "core/Log.hpp"
#include "shell/Bar.hpp"
#include "wayland/WaylandConnection.hpp"

#include <cerrno>
#include <poll.h>
#include <stdexcept>

#include <wayland-client-core.h>

MainLoop::MainLoop(WaylandConnection& wayland, Bar& bar, std::vector<PollSource*> sources)
    : m_wayland(wayland)
    , m_bar(bar)
    , m_sources(std::move(sources)) {}

void MainLoop::run() {
    while (m_bar.isRunning() && !Application::s_shutdownRequested) {
        if (wl_display_dispatch_pending(m_wayland.display()) < 0) {
            throw std::runtime_error("failed to dispatch pending Wayland events");
        }
        if (wl_display_flush(m_wayland.display()) < 0) {
            throw std::runtime_error("failed to flush Wayland display");
        }

        // Collect poll fds and compute timeout from all sources
        std::vector<pollfd> pollFds;
        pollFds.push_back({.fd = wl_display_get_fd(m_wayland.display()), .events = POLLIN, .revents = 0});

        int pollTimeout = -1;
        std::vector<std::size_t> sourceStartIndices;
        sourceStartIndices.reserve(m_sources.size());

        for (auto* source : m_sources) {
            sourceStartIndices.push_back(source->addPollFds(pollFds));

            const int t = source->pollTimeoutMs();
            if (t >= 0 && (pollTimeout < 0 || t < pollTimeout)) {
                pollTimeout = t;
            }
        }

        const int pollResult = ::poll(pollFds.data(), pollFds.size(), pollTimeout);
        if (pollResult < 0) {
            if (errno == EINTR) {
                continue;
            }
            throw std::runtime_error("failed to poll fds");
        }

        // Dispatch Wayland events
        if ((pollFds[0].revents & POLLIN) != 0) {
            if (wl_display_dispatch(m_wayland.display()) < 0) {
                throw std::runtime_error("failed to dispatch Wayland events");
            }
        } else {
            if (wl_display_dispatch_pending(m_wayland.display()) < 0) {
                throw std::runtime_error("failed to dispatch pending Wayland events");
            }
        }

        // Dispatch all sources
        for (std::size_t i = 0; i < m_sources.size(); ++i) {
            m_sources[i]->dispatch(pollFds, sourceStartIndices[i]);
        }
    }

    // Close all UI surfaces immediately and flush Wayland to make them disappear
    logDebug("closing bar surfaces for clean shutdown");
    m_bar.closeAllInstances();

    if (wl_display_dispatch_pending(m_wayland.display()) < 0) {
        logWarn("failed to dispatch pending Wayland events during shutdown");
    }
    if (wl_display_flush(m_wayland.display()) < 0) {
        logWarn("failed to flush Wayland display during shutdown");
    }
}
