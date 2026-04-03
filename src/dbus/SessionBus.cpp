#include "dbus/SessionBus.hpp"

SessionBus::SessionBus()
    : m_connection(sdbus::createSessionBusConnection()) {}

sdbus::IConnection::PollData SessionBus::getPollData() const {
    return m_connection->getEventLoopPollData();
}

void SessionBus::processPendingEvents() {
    while (m_connection->processPendingEvent()) {}
}
