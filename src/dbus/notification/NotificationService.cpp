#include "NotificationService.hpp"

#include <stdexcept>

static const sdbus::ServiceName k_bus_name   {"org.freedesktop.Notifications"};
static const sdbus::ObjectPath  k_object_path{"/org/freedesktop/Notifications"};
static constexpr auto           k_interface  = "org.freedesktop.Notifications";
static constexpr uint32_t       k_close_reason_closed_by_call = 3;

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
            }),

        sdbus::registerMethod("CloseNotification")
            .withInputParamNames("id")
            .implementedAs([this](uint32_t id) {
                onCloseNotification(id);
            })
    ).forInterface(k_interface);
}

void NotificationService::run() {
    m_connection->enterEventLoop();
}

uint32_t NotificationService::onNotify(const std::string& app_name,
                                        uint32_t           replaces_id,
                                        const std::string& app_icon,
                                        const std::string& summary,
                                        const std::string& body,
                                        const std::vector<std::string>& /*actions*/,
                                        const std::map<std::string, sdbus::Variant>& hints,
                                        int32_t expire_timeout) {
    Urgency urgency = Urgency::Normal;
    if (auto it = hints.find("urgency"); it != hints.end()) {
        urgency = static_cast<Urgency>(it->second.get<uint8_t>());
    }

    std::optional<std::string> icon;
    if (!app_icon.empty()) {
        icon = app_icon;
    }
    if (auto it = hints.find("image-path"); it != hints.end()) {
        try {
            icon = it->second.get<std::string>();
        } catch (...) {}
    }

    std::optional<std::string> category;
    if (auto it = hints.find("category"); it != hints.end()) {
        try {
            category = it->second.get<std::string>();
        } catch (...) {}
    }

    std::optional<std::string> desktop_entry;
    if (auto it = hints.find("desktop-entry"); it != hints.end()) {
        try {
            desktop_entry = it->second.get<std::string>();
        } catch (...) {}
    }

    return m_manager.addOrReplace(replaces_id, app_name, summary, body,
                                  expire_timeout, urgency, icon, category, desktop_entry);
}

std::vector<std::string> NotificationService::onGetCapabilities() {
    return {"body"};
}

void NotificationService::onCloseNotification(uint32_t id) {
    if (!m_manager.close(id)) {
        return;
    }

    m_object->emitSignal("NotificationClosed")
        .onInterface(k_interface)
        .withArguments(id, k_close_reason_closed_by_call);
}

std::tuple<std::string, std::string, std::string, std::string>
NotificationService::onGetServerInformation() {
    return {"noctalia", "noctalia-dev", "0.1.0", "1.2"};
}
