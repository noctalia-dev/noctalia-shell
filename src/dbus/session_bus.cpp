#include "dbus/session_bus.h"

SessionBus::SessionBus() : m_connection(sdbus::createSessionBusConnection()) {}

sdbus::IConnection::PollData SessionBus::getPollData() const { return m_connection->getEventLoopPollData(); }

void SessionBus::processPendingEvents() {
  while (m_connection->processPendingEvent()) {
  }
}
