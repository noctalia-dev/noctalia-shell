#include "app/MainLoop.hpp"

#include "app/Application.hpp"
#include "dbus/SessionBus.hpp"
#include "dbus/notification/NotificationService.hpp"
#include "shell/Bar.hpp"

#include <cerrno>
#include <poll.h>
#include <stdexcept>

MainLoop::MainLoop(Bar& bar, SessionBus* bus, NotificationService* notifications)
    : m_bar(bar)
    , m_bus(bus)
    , m_notifications(notifications) {}

void MainLoop::run() {
    while (m_bar.isRunning() && !Application::s_shutdown_requested) {
        m_bar.dispatchPending();
        m_bar.flush();

        int pollTimeout = -1;
        if (m_notifications != nullptr) {
            const int expiryTimeout = m_notifications->nextExpiryTimeoutMs();
            if (expiryTimeout >= 0) {
                pollTimeout = expiryTimeout;
            }
        }

        if (m_bus != nullptr) {
            auto dbusPollData = m_bus->getPollData();
            const int dbusTimeout = dbusPollData.getPollTimeout();
            if (dbusTimeout >= 0 && (pollTimeout < 0 || dbusTimeout < pollTimeout)) {
                pollTimeout = dbusTimeout;
            }

            struct pollfd pollFds[] = {
                {.fd = m_bar.displayFd(), .events = POLLIN, .revents = 0},
                {.fd = dbusPollData.fd, .events = dbusPollData.events, .revents = 0},
                {.fd = dbusPollData.eventFd, .events = POLLIN, .revents = 0},
            };

            const int pollResult = ::poll(pollFds, 3, pollTimeout);
            if (pollResult < 0) {
                if (errno == EINTR) {
                    continue;  // Signal received, check shutdown flag
                }
                throw std::runtime_error("failed to poll fds");
            }

            if ((pollFds[0].revents & POLLIN) != 0) {
                m_bar.dispatchReadable();
            } else {
                m_bar.dispatchPending();
            }

            m_bus->processPendingEvents();
        } else {
            struct pollfd pollFd = {.fd = m_bar.displayFd(), .events = POLLIN, .revents = 0};

            const int pollResult = ::poll(&pollFd, 1, pollTimeout);
            if (pollResult < 0) {
                if (errno == EINTR) {
                    continue;  // Signal received, check shutdown flag
                }
                throw std::runtime_error("failed to poll wayland fd");
            }

            if ((pollFd.revents & POLLIN) != 0) {
                m_bar.dispatchReadable();
            }
        }

        if (m_notifications != nullptr) {
            m_notifications->processExpiredNotifications();
        }
    }
}
