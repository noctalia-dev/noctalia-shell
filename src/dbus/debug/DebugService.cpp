#include "dbus/debug/DebugService.hpp"

#include "core/Log.hpp"
#include "dbus/SessionBus.hpp"

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

}

DebugService::DebugService(SessionBus& bus, InternalNotificationService& internal_notifications)
    : m_internal_notifications(internal_notifications) {
    bus.connection().requestName(k_debug_bus_name);
    m_object = sdbus::createObject(bus.connection(), k_debug_object_path);

    m_object->addVTable(
        sdbus::registerMethod("EmitInternalNotification")
            .withInputParamNames("app_name", "summary", "body", "timeout", "urgency")
            .withOutputParamNames("id")
            .implementedAs([this](const std::string& app_name,
                                  const std::string& summary,
                                  const std::string& body,
                                  int32_t timeout,
                                  uint8_t urgency) {
                return onEmitInternalNotification(app_name, summary, body, timeout, urgency);
            })
    ).forInterface(k_debug_interface);
}

uint32_t DebugService::onEmitInternalNotification(const std::string& app_name,
                                                  const std::string& summary,
                                                  const std::string& body,
                                                  int32_t timeout,
                                                  uint8_t urgency) {
    const uint32_t id = m_internal_notifications.notify(app_name,
                                                        summary,
                                                        body,
                                                        timeout,
                                                        clamp_urgency(urgency));
    logInfo("debug internal notification emitted id={} app=\"{}\"", id, app_name);
    return id;
}