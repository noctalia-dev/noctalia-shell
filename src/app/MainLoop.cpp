#include "app/MainLoop.hpp"

#include "app/Application.hpp"
#include "config/ConfigService.hpp"
#include "config/StateService.hpp"
#include "core/Log.hpp"
#include "dbus/SessionBus.hpp"
#include "dbus/notification/NotificationService.hpp"
#include "shell/Bar.hpp"
#include "time/TimeService.hpp"
#include "wayland/WaylandConnection.hpp"

#include <cerrno>
#include <poll.h>
#include <stdexcept>

#include <wayland-client-core.h>

MainLoop::MainLoop(WaylandConnection& wayland, Bar& bar, SessionBus* bus,
                   NotificationService* notifications, TimeService* time,
                   ConfigService* config, StateService* state)
    : m_wayland(wayland)
    , m_bar(bar)
    , m_bus(bus)
    , m_notifications(notifications)
    , m_time(time)
    , m_config(config)
    , m_state(state) {}

void MainLoop::run() {
    while (m_bar.isRunning() && !Application::s_shutdown_requested) {
        if (wl_display_dispatch_pending(m_wayland.display()) < 0) {
            throw std::runtime_error("failed to dispatch pending Wayland events");
        }
        if (wl_display_flush(m_wayland.display()) < 0) {
            throw std::runtime_error("failed to flush Wayland display");
        }

        // Check if shutdown was requested since the last iteration
        if (Application::s_shutdown_requested) {
            break;
        }

        int pollTimeout = -1;
        if (m_time != nullptr) {
            pollTimeout = m_time->pollTimeoutMs();
        }
        if (m_notifications != nullptr) {
            const int expiryTimeout = m_notifications->nextExpiryTimeoutMs();
            if (expiryTimeout >= 0 && (pollTimeout < 0 || expiryTimeout < pollTimeout)) {
                pollTimeout = expiryTimeout;
            }
        }

        // Build poll fd list
        std::vector<pollfd> pollFds;
        pollFds.push_back({.fd = wl_display_get_fd(m_wayland.display()), .events = POLLIN, .revents = 0});

        if (m_bus != nullptr) {
            auto dbusPollData = m_bus->getPollData();
            const int dbusTimeout = dbusPollData.getPollTimeout();
            if (dbusTimeout >= 0 && (pollTimeout < 0 || dbusTimeout < pollTimeout)) {
                pollTimeout = dbusTimeout;
            }
            pollFds.push_back({.fd = dbusPollData.fd, .events = dbusPollData.events, .revents = 0});
            pollFds.push_back({.fd = dbusPollData.eventFd, .events = POLLIN, .revents = 0});
        }

        int configFdIdx = -1;
        if (m_config != nullptr && m_config->watchFd() >= 0) {
            configFdIdx = static_cast<int>(pollFds.size());
            pollFds.push_back({.fd = m_config->watchFd(), .events = POLLIN, .revents = 0});
        }

        int stateFdIdx = -1;
        if (m_state != nullptr && m_state->watchFd() >= 0) {
            stateFdIdx = static_cast<int>(pollFds.size());
            pollFds.push_back({.fd = m_state->watchFd(), .events = POLLIN, .revents = 0});
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

        // Dispatch D-Bus events
        if (m_bus != nullptr) {
            m_bus->processPendingEvents();
        }

        // Check config file changes
        if (configFdIdx >= 0 && (pollFds[static_cast<std::size_t>(configFdIdx)].revents & POLLIN) != 0) {
            m_config->checkReload();
        }

        // Check state file changes
        if (stateFdIdx >= 0 && (pollFds[static_cast<std::size_t>(stateFdIdx)].revents & POLLIN) != 0) {
            m_state->checkReload();
        }

        if (m_time != nullptr) {
            m_time->tickSecond();
        }

        if (m_notifications != nullptr) {
            m_notifications->processExpiredNotifications();
        }
    }

    // Close all UI surfaces immediately and flush Wayland to make them disappear
    // This happens while we're still in a valid Wayland/display context
    logDebug("closing bar surfaces for clean shutdown");
    m_bar.closeAllInstances();
    
    // Dispatch any pending surface destroy messages and flush to compositor
    if (wl_display_dispatch_pending(m_wayland.display()) < 0) {
        logWarn("failed to dispatch pending Wayland events during shutdown");
    }
    if (wl_display_flush(m_wayland.display()) < 0) {
        logWarn("failed to flush Wayland display during shutdown");
    }
}
