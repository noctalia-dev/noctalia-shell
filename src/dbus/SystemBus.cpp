#include "dbus/SystemBus.h"

SystemBus::SystemBus() : m_connection(sdbus::createSystemBusConnection()) {}

sdbus::IConnection::PollData SystemBus::getPollData() const { return m_connection->getEventLoopPollData(); }

void SystemBus::processPendingEvents() {
  while (m_connection->processPendingEvent()) {
  }
}
