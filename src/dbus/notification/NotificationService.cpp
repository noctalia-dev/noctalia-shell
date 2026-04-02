#include "NotificationService.hpp"

#include <poll.h>
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
            }),

        sdbus::registerMethod("CloseNotification")
            .withInputParamNames("id")
            .implementedAs([this](uint32_t id) {
                onCloseNotification(id);
            }),

        sdbus::registerSignal("NotificationClosed")
            .withParameters<uint32_t, uint32_t>("id", "reason"),

        sdbus::registerSignal("ActionInvoked")
            .withParameters<uint32_t, std::string>("id", "action_key")
    ).forInterface(k_interface);
}

void NotificationService::run() {
    // Manual event loop so we can tick expiry between D-Bus events.
    while (true) {
        auto poll_data = m_connection->getEventLoopPollData();

        // Compute how long until the next notification expires.
        int expiry_ms = -1;
        const auto now = Clock::now();
        for (const auto& n : m_manager.all()) {
            if (n.expiry_time) {
                const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                    *n.expiry_time - now).count();
                const int clamped = static_cast<int>(std::max<long long>(0, ms));
                if (expiry_ms < 0 || clamped < expiry_ms) {
                    expiry_ms = clamped;
                }
            }
        }

        // Poll for D-Bus events or until next expiry.
        // getPollTimeout() may return -1 (indefinite); treat it as infinity so
        // our expiry deadline always wins when set.
        const int dbus_timeout = poll_data.getPollTimeout();
        int poll_timeout;
        if (expiry_ms >= 0 && dbus_timeout < 0) {
            poll_timeout = expiry_ms;
        } else if (expiry_ms >= 0) {
            poll_timeout = std::min(expiry_ms, dbus_timeout);
        } else {
            poll_timeout = dbus_timeout;
        }

        struct pollfd pfd{.fd = poll_data.fd, .events = poll_data.events, .revents = 0};
        ::poll(&pfd, 1, poll_timeout);

        // Process any pending D-Bus messages.
        while (m_connection->processPendingEvent()) {}

        // Expire timed-out notifications.
        for (const uint32_t id : m_manager.expiredIds()) {
            emitClose(id, CloseReason::Expired);
            m_manager.close(id, CloseReason::Expired);
        }
    }
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
    return {"body", "actions"};
}

void NotificationService::onCloseNotification(uint32_t id) {
    if (!m_manager.close(id, CloseReason::ClosedByCall)) {
        return;
    }
    emitClose(id, CloseReason::ClosedByCall);
}

void NotificationService::emitClose(uint32_t id, CloseReason reason) {
    m_object->emitSignal("NotificationClosed")
        .onInterface(k_interface)
        .withArguments(id, static_cast<uint32_t>(reason));
}

std::tuple<std::string, std::string, std::string, std::string>
NotificationService::onGetServerInformation() {
    return {"noctalia", "noctalia-dev", "0.1.0", "1.2"};
}
