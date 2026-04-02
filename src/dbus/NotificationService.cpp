#include "NotificationService.hpp"

#include <stdexcept>

static const sdbus::ServiceName k_bus_name   {"org.freedesktop.Notifications"};
static const sdbus::ObjectPath  k_object_path{"/org/freedesktop/Notifications"};
static constexpr auto           k_interface  = "org.freedesktop.Notifications";

NotificationService::NotificationService(NotificationManager& manager)
    : m_manager(manager)
{
    m_connection = sdbus::createSessionBusConnection(k_bus_name);
    m_object     = sdbus::createObject(*m_connection, k_object_path);

    m_object->addVTable(
        sdbus::registerMethod("Notify")
            .withInputParamNames("app_name", "replaces_id", "app_icon",
                                 "summary", "body", "actions", "hints",
                                 "expire_timeout")
            .withOutputParamNames("id")
            .implementedAs([this](const std::string& app_name,
                                  uint32_t           replaces_id,
                                  const std::string& app_icon,
                                  const std::string& summary,
                                  const std::string& body,
                                  const std::vector<std::string>& actions,
                                  const std::map<std::string, sdbus::Variant>& hints,
                                  int32_t expire_timeout) {
                return onNotify(app_name, replaces_id, app_icon,
                                summary, body, actions, hints, expire_timeout);
            }),

        sdbus::registerMethod("GetCapabilities")
            .withOutputParamNames("capabilities")
            .implementedAs([this]() {
                return onGetCapabilities();
            }),

        sdbus::registerMethod("GetServerInformation")
            .withOutputParamNames("name", "vendor", "version", "spec_version")
            .implementedAs([this]() {
                return onGetServerInformation();
            })
    ).forInterface(k_interface);
}

void NotificationService::run() {
    m_connection->enterEventLoop();
}

uint32_t NotificationService::onNotify(const std::string& app_name,
                                        uint32_t           replaces_id,
                                        const std::string& /*app_icon*/,
                                        const std::string& summary,
                                        const std::string& body,
                                        const std::vector<std::string>& /*actions*/,
                                        const std::map<std::string, sdbus::Variant>& hints,
                                        int32_t expire_timeout) {
    Urgency urgency = Urgency::Normal;
    if (auto it = hints.find("urgency"); it != hints.end()) {
        urgency = static_cast<Urgency>(it->second.get<uint8_t>());
    }

    return m_manager.addOrReplace(replaces_id, app_name, summary, body, expire_timeout, urgency);
}

std::vector<std::string> NotificationService::onGetCapabilities() {
    return {"body"};
}

std::tuple<std::string, std::string, std::string, std::string>
NotificationService::onGetServerInformation() {
    return {"noctalia", "noctalia-dev", "0.1.0", "1.2"};
}
