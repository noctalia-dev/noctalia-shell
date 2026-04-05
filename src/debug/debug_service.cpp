#include "debug/debug_service.h"

#include "core/log.h"
#include "dbus/session_bus.h"

namespace {

static const sdbus::ServiceName k_debug_bus_name{"dev.noctalia.Debug"};
static const sdbus::ObjectPath k_debug_object_path{"/dev/noctalia/Debug"};
static constexpr auto k_debug_interface = "dev.noctalia.Debug";

Urgency clamp_urgency(uint8_t urgency) {
  if (urgency > static_cast<uint8_t>(Urgency::Critical)) {
    return Urgency::Normal;
  }
  return static_cast<Urgency>(urgency);
}

} // namespace

DebugService::DebugService(SessionBus& bus, NotificationManager& notifications) : m_notifications(notifications) {
  bus.connection().requestName(k_debug_bus_name);
  m_object = sdbus::createObject(bus.connection(), k_debug_object_path);

  m_object
      ->addVTable(sdbus::registerMethod("EmitInternalNotification")
                      .withInputParamNames("app_name", "summary", "body", "timeout", "urgency")
                      .withOutputParamNames("id")
                      .implementedAs([this](const std::string& app_name, const std::string& summary,
                                            const std::string& body, int32_t timeout, uint8_t urgency) {
                        return onEmitInternalNotification(app_name, summary, body, timeout, urgency);
                      }),

                  sdbus::registerMethod("SetVerboseLogs")
                      .withInputParamNames("enabled")
                      .withOutputParamNames("success")
                      .implementedAs([this](bool enabled) { return onSetVerboseLogs(enabled); }),

                  sdbus::registerMethod("GetVerboseLogs").withOutputParamNames("enabled").implementedAs([this]() {
                    return onGetVerboseLogs();
                  }))
      .forInterface(k_debug_interface);
}

uint32_t DebugService::onEmitInternalNotification(const std::string& app_name, const std::string& summary,
                                                  const std::string& body, int32_t timeout, uint8_t urgency) {
  const uint32_t id = m_notifications.addInternal(app_name, summary, body, timeout, clamp_urgency(urgency));
  logInfo("debug internal notification emitted id={} app=\"{}\"", id, app_name);
  return id;
}

bool DebugService::onSetVerboseLogs(bool enabled) {
  m_verbose_logs = enabled;
  setLogLevel(enabled ? LogLevel::Debug : LogLevel::Info);
  logInfo("debug verbose logs {}", enabled ? "enabled" : "disabled");
  return true;
}

bool DebugService::onGetVerboseLogs() const { return m_verbose_logs; }
