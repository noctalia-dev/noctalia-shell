#include "app/MainLoop.hpp"

#include "dbus/notification/NotificationService.hpp"
#include "shell/Bar.hpp"

#include <poll.h>
#include <stdexcept>

MainLoop::MainLoop(Bar& bar, NotificationService* notifications)
    : m_bar(bar)
    , m_notifications(notifications) {}

void MainLoop::run() {
    if (m_notifications == nullptr) {
        m_bar.run();
        return;
    }

    while (m_bar.isRunning()) {
        m_bar.dispatchPending();
        m_bar.flush();

        auto dbusPollData = m_notifications->getPollData();
        const int dbusTimeout = dbusPollData.getPollTimeout();
        const int expiryTimeout = m_notifications->nextExpiryTimeoutMs();

        int pollTimeout = dbusTimeout;
        if (expiryTimeout >= 0 && (pollTimeout < 0 || expiryTimeout < pollTimeout)) {
            pollTimeout = expiryTimeout;
        }

        struct pollfd pollFds[] = {
            {.fd = m_bar.displayFd(), .events = POLLIN, .revents = 0},
            {.fd = dbusPollData.fd, .events = dbusPollData.events, .revents = 0},
            {.fd = dbusPollData.eventFd, .events = POLLIN, .revents = 0},
        };

        if (::poll(pollFds, 3, pollTimeout) < 0) {
            throw std::runtime_error("failed to poll shell and notification fds");
        }

        if ((pollFds[0].revents & POLLIN) != 0) {
            m_bar.dispatchReadable();
        } else {
            m_bar.dispatchPending();
        }

        m_notifications->processPendingEvents();
        m_notifications->processExpiredNotifications();
    }
}
