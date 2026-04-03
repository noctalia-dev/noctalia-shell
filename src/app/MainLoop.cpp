#include "app/MainLoop.hpp"

#include "app/Application.hpp"
#include "config/ConfigService.hpp"
#include "dbus/SessionBus.hpp"
#include "dbus/notification/NotificationService.hpp"
#include "shell/Bar.hpp"
#include "time/TimeService.hpp"

#include <cerrno>
#include <poll.h>
#include <stdexcept>

MainLoop::MainLoop(Bar& bar, SessionBus* bus, NotificationService* notifications,
                   TimeService* time, ConfigService* config)
    : m_bar(bar)
    , m_bus(bus)
    , m_notifications(notifications)
    , m_time(time)
    , m_config(config) {}

void MainLoop::run() {
    while (m_bar.isRunning() && !Application::s_shutdown_requested) {
        m_bar.dispatchPending();
        m_bar.flush();

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
        pollFds.push_back({.fd = m_bar.displayFd(), .events = POLLIN, .revents = 0});

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

        const int pollResult = ::poll(pollFds.data(), pollFds.size(), pollTimeout);
        if (pollResult < 0) {
            if (errno == EINTR) {
                continue;
            }
            throw std::runtime_error("failed to poll fds");
        }

        // Dispatch Wayland events
        if ((pollFds[0].revents & POLLIN) != 0) {
            m_bar.dispatchReadable();
        } else {
            m_bar.dispatchPending();
        }

        // Dispatch D-Bus events
        if (m_bus != nullptr) {
            m_bus->processPendingEvents();
        }

        // Check config file changes
        if (configFdIdx >= 0 && (pollFds[static_cast<std::size_t>(configFdIdx)].revents & POLLIN) != 0) {
            m_config->checkReload();
        }

        if (m_time != nullptr) {
            m_time->tick();
        }

        if (m_notifications != nullptr) {
            m_notifications->processExpiredNotifications();
        }
    }
}
