#include "dbus/logind/logind_service.h"

#include "core/log.h"
#include "dbus/system_bus.h"

#include <cstdlib>
#include <optional>
#include <sdbus-c++/Error.h>
#include <sdbus-c++/IProxy.h>
#include <sdbus-c++/Types.h>
#include <string>
#include <unistd.h>
#include <utility>

namespace {
  constexpr Logger kLog("logind");

  const sdbus::ServiceName kLogindBusName{"org.freedesktop.login1"};
  const sdbus::ObjectPath kLogindObjectPath{"/org/freedesktop/login1"};
  constexpr auto kLogindManagerInterface = "org.freedesktop.login1.Manager";
  constexpr auto kLogindSessionInterface = "org.freedesktop.login1.Session";

  [[nodiscard]] std::optional<sdbus::ObjectPath> resolveSessionPath(sdbus::IConnection& connection) {
    try {
      auto managerProxy = sdbus::createProxy(connection, kLogindBusName, kLogindObjectPath);

      if (const char* sessionId = std::getenv("XDG_SESSION_ID"); sessionId != nullptr && sessionId[0] != '\0') {
        try {
          sdbus::ObjectPath sessionPath;
          managerProxy->callMethod("GetSession")
              .onInterface(kLogindManagerInterface)
              .withArguments(std::string(sessionId))
              .storeResultsTo(sessionPath);
          return sessionPath;
        } catch (const sdbus::Error& e) {
          kLog.debug("failed to resolve logind session via XDG_SESSION_ID={}: {}", sessionId, e.what());
        }
      }

      sdbus::ObjectPath sessionPath;
      managerProxy->callMethod("GetSessionByPID")
          .onInterface(kLogindManagerInterface)
          .withArguments(static_cast<std::uint32_t>(::getpid()))
          .storeResultsTo(sessionPath);
      return sessionPath;
    } catch (const sdbus::Error& e) {
      kLog.warn("failed to resolve logind session: {}", e.what());
      return std::nullopt;
    }
  }
} // namespace

LogindService::LogindService(SystemBus& bus) : m_bus(bus) {
  m_managerProxy = sdbus::createProxy(m_bus.connection(), kLogindBusName, kLogindObjectPath);
  m_managerProxy->uponSignal("PrepareForSleep").onInterface(kLogindManagerInterface).call([this](bool sleeping) {
    if (m_prepareForSleepCallback) {
      m_prepareForSleepCallback(sleeping);
    }
  });

  const auto sessionPath = resolveSessionPath(m_bus.connection());
  if (!sessionPath.has_value()) {
    kLog.warn("logind session lock monitor disabled: session path unavailable");
    return;
  }

  m_sessionProxy = sdbus::createProxy(m_bus.connection(), kLogindBusName, *sessionPath);
  m_sessionProxy->uponSignal("Lock").onInterface(kLogindSessionInterface).call([this]() {
    if (m_lockCallback) {
      m_lockCallback();
    }
  });
  m_sessionProxy->uponSignal("Unlock").onInterface(kLogindSessionInterface).call([this]() {
    if (m_unlockCallback) {
      m_unlockCallback();
    }
  });
  kLog.info("logind session lock monitor active ({})", std::string(sessionPath->c_str()));
}

void LogindService::setPrepareForSleepCallback(PrepareForSleepCallback callback) {
  m_prepareForSleepCallback = std::move(callback);
}

void LogindService::setLockCallback(SessionLockCallback callback) { m_lockCallback = std::move(callback); }

void LogindService::setUnlockCallback(SessionLockCallback callback) { m_unlockCallback = std::move(callback); }

void LogindService::syncSessionLocked() {
  if (m_sessionProxy == nullptr) {
    return;
  }
  try {
    m_sessionProxy->callMethod("Lock").onInterface(kLogindSessionInterface);
    kLog.debug("logind session lock state synced");
  } catch (const sdbus::Error& e) {
    kLog.warn("failed to sync logind session lock state: {}", e.what());
  }
}

void LogindService::syncSessionUnlocked() {
  if (m_sessionProxy == nullptr) {
    return;
  }
  try {
    m_sessionProxy->callMethod("Unlock").onInterface(kLogindSessionInterface);
    kLog.debug("logind session unlock state synced");
  } catch (const sdbus::Error& e) {
    kLog.warn("failed to sync logind session unlock state: {}", e.what());
  }
}
