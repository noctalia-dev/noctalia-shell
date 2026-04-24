#include "notification_service.h"

#include "core/log.h"
#include "dbus/session_bus.h"

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <tuple>

namespace {
  constexpr Logger kLog("notification");
} // namespace

static const sdbus::ServiceName k_bus_name{"org.freedesktop.Notifications"};
static const sdbus::ObjectPath k_object_path{"/org/freedesktop/Notifications"};
static constexpr auto k_interface = "org.freedesktop.Notifications";

NotificationService::NotificationService(SessionBus& bus, NotificationManager& manager) : m_manager(manager) {
  m_manager.setActionInvokeCallback(
      [this](uint32_t id, const std::string& actionKey) { emitActionInvoked(id, actionKey); });

  bus.connection().requestName(k_bus_name);
  m_object = sdbus::createObject(bus.connection(), k_object_path);

  m_object
      ->addVTable(
          sdbus::registerMethod("Notify")
              .withInputParamNames("app_name", "replaces_id", "app_icon", "summary", "body", "actions", "hints",
                                   "expire_timeout")
              .withOutputParamNames("id")
              .implementedAs([this](const std::string& app_name, uint32_t replaces_id, const std::string& app_icon,
                                    const std::string& summary, const std::string& body,
                                    const std::vector<std::string>& actions,
                                    const std::map<std::string, sdbus::Variant>& hints, int32_t expire_timeout) {
                return onNotify(app_name, replaces_id, app_icon, summary, body, actions, hints, expire_timeout);
              }),

          sdbus::registerMethod("GetCapabilities").withOutputParamNames("capabilities").implementedAs([this]() {
            return onGetCapabilities();
          }),

          sdbus::registerMethod("GetNotifications").withOutputParamNames("notifications").implementedAs([this]() {
            return onGetNotifications();
          }),

          sdbus::registerMethod("GetServerInformation")
              .withOutputParamNames("name", "vendor", "version", "spec_version")
              .implementedAs([this]() { return onGetServerInformation(); }),

          sdbus::registerMethod("CloseNotification").withInputParamNames("id").implementedAs([this](uint32_t id) {
            onCloseNotification(id);
          }),

          sdbus::registerMethod("InvokeAction")
              .withInputParamNames("id", "action_key")
              .implementedAs([this](uint32_t id, const std::string& actionKey) { onInvokeAction(id, actionKey); }),

          sdbus::registerSignal("NotificationClosed").withParameters<uint32_t, uint32_t>("id", "reason"),

          sdbus::registerSignal("ActionInvoked").withParameters<uint32_t, std::string>("id", "action_key"))
      .forInterface(k_interface);
}

void NotificationService::processExpired() {
  for (const uint32_t id : m_manager.expiredIds()) {
    emitClose(id, CloseReason::Expired);
    m_manager.close(id, CloseReason::Expired);
  }
}

static constexpr size_t k_max_string_len = 1024;
static constexpr int32_t k_min_timeout = -1;

namespace {

  std::string clamp_str(std::string_view s) {
    const auto len = std::min(s.size(), k_max_string_len);
    return std::string{s.substr(0, len)};
  }

  bool isBlankText(std::string_view text) {
    return text.empty() ||
           std::all_of(text.begin(), text.end(), [](unsigned char ch) { return std::isspace(ch) != 0; });
  }

  std::vector<std::string> sanitize_actions(const std::vector<std::string>& actions) {
    static constexpr std::string_view kFallbackActionLabel = "Action";

    std::vector<std::string> sanitized;
    sanitized.reserve(actions.size() - (actions.size() % 2));

    for (size_t i = 0; i + 1 < actions.size(); i += 2) {
      std::string actionKey = clamp_str(actions[i]);
      std::string label = clamp_str(actions[i + 1]);

      if (actionKey.empty()) {
        continue;
      }

      if (isBlankText(label)) {
        label = kFallbackActionLabel;
      }

      sanitized.push_back(std::move(actionKey));
      sanitized.push_back(std::move(label));
    }

    return sanitized;
  }

  using NotificationImageDataStruct = sdbus::Struct<std::int32_t, std::int32_t, std::int32_t, bool, std::int32_t,
                                                    std::int32_t, std::vector<std::uint8_t>>;

  std::optional<NotificationImageData> decode_image_data_variant(const sdbus::Variant& value) {
    try {
      const auto data = value.get<NotificationImageDataStruct>();
      NotificationImageData out;
      out.width = std::get<0>(data);
      out.height = std::get<1>(data);
      out.rowStride = std::get<2>(data);
      out.hasAlpha = std::get<3>(data);
      out.bitsPerSample = std::get<4>(data);
      out.channels = std::get<5>(data);
      out.data = std::get<6>(data);
      return out;
    } catch (const sdbus::Error&) {
    }

    try {
      const auto data = value.get<std::tuple<std::int32_t, std::int32_t, std::int32_t, bool, std::int32_t, std::int32_t,
                                             std::vector<std::uint8_t>>>();
      NotificationImageData out;
      out.width = std::get<0>(data);
      out.height = std::get<1>(data);
      out.rowStride = std::get<2>(data);
      out.hasAlpha = std::get<3>(data);
      out.bitsPerSample = std::get<4>(data);
      out.channels = std::get<5>(data);
      out.data = std::get<6>(data);
      return out;
    } catch (const sdbus::Error&) {
    }

    return std::nullopt;
  }

  std::optional<NotificationImageData> decode_image_hint(const std::map<std::string, sdbus::Variant>& hints,
                                                         std::string* outSourceKey = nullptr) {
    for (const char* key : {"image-data", "image_data", "icon_data"}) {
      const auto it = hints.find(key);
      if (it == hints.end()) {
        continue;
      }

      auto decoded = decode_image_data_variant(it->second);
      if (decoded.has_value()) {
        if (outSourceKey != nullptr) {
          *outSourceKey = key;
        }
        return decoded;
      }
    }

    return std::nullopt;
  }

} // namespace

uint32_t NotificationService::onNotify(const std::string& app_name, uint32_t replaces_id, const std::string& app_icon,
                                       const std::string& summary, const std::string& body,
                                       const std::vector<std::string>& actions,
                                       const std::map<std::string, sdbus::Variant>& hints, int32_t expire_timeout) {
  // Sanitize scalar inputs
  const int32_t timeout = std::max(expire_timeout, k_min_timeout);
  const auto sanitizedActions = sanitize_actions(actions);

  // Urgency: default Normal, reject out-of-range byte values
  Urgency urgency = Urgency::Normal;
  if (auto it = hints.find("urgency"); it != hints.end()) {
    try {
      const uint8_t raw = it->second.get<uint8_t>();
      if (raw <= static_cast<uint8_t>(Urgency::Critical)) {
        urgency = static_cast<Urgency>(raw);
      }
    } catch (...) {
    }
  }

  std::optional<std::string> icon;
  if (!app_icon.empty()) {
    icon = clamp_str(app_icon);
  }
  if (auto it = hints.find("image-path"); it != hints.end()) {
    try {
      icon = clamp_str(it->second.get<std::string>());
    } catch (...) {
    }
  }
  if (auto it = hints.find("image_path"); it != hints.end()) {
    try {
      icon = clamp_str(it->second.get<std::string>());
    } catch (...) {
    }
  }

  std::optional<std::string> category;
  if (auto it = hints.find("category"); it != hints.end()) {
    try {
      category = clamp_str(it->second.get<std::string>());
    } catch (...) {
    }
  }

  std::optional<std::string> desktop_entry;
  if (auto it = hints.find("desktop-entry"); it != hints.end()) {
    try {
      desktop_entry = clamp_str(it->second.get<std::string>());
    } catch (...) {
    }
  }

  std::optional<NotificationImageData> imageData = decode_image_hint(hints);

  return m_manager.addOrReplace(replaces_id, clamp_str(app_name), clamp_str(summary), clamp_str(body), urgency, timeout,
                                NotificationOrigin::External, sanitizedActions, icon, imageData, category,
                                desktop_entry);
}

std::vector<std::string> NotificationService::onGetCapabilities() { return {"body", "actions"}; }

std::vector<std::map<std::string, sdbus::Variant>> NotificationService::onGetNotifications() {
  std::vector<std::map<std::string, sdbus::Variant>> result;
  for (const auto& n : m_manager.all()) {
    std::map<std::string, sdbus::Variant> notif;
    notif["id"] = sdbus::Variant(n.id);
    notif["app_name"] = sdbus::Variant(n.appName);
    notif["summary"] = sdbus::Variant(n.summary);
    notif["body"] = sdbus::Variant(n.body);
    notif["timeout"] = sdbus::Variant(n.timeout);
    notif["urgency"] = sdbus::Variant(static_cast<uint8_t>(n.urgency));
    notif["actions"] = sdbus::Variant(n.actions);
    notif["icon"] = sdbus::Variant(n.icon.value_or(""));
    notif["category"] = sdbus::Variant(n.category.value_or(""));
    notif["desktop_entry"] = sdbus::Variant(n.desktopEntry.value_or(""));
    result.push_back(notif);
  }
  return result;
}

void NotificationService::onCloseNotification(uint32_t id) {
  if (!m_manager.close(id, CloseReason::ClosedByCall)) {
    throw sdbus::Error(sdbus::Error::Name{"org.freedesktop.Notifications.Error.NotFound"},
                       "notification id was not found");
  }
  emitClose(id, CloseReason::ClosedByCall);
}

void NotificationService::emitClose(uint32_t id, CloseReason reason) {
  m_object->emitSignal("NotificationClosed").onInterface(k_interface).withArguments(id, static_cast<uint32_t>(reason));
}

void NotificationService::onInvokeAction(uint32_t id, const std::string& actionKey) {
  const std::string sanitizedKey = clamp_str(actionKey);
  if (sanitizedKey.empty()) {
    throw sdbus::Error(sdbus::Error::Name{"org.freedesktop.Notifications.Error.InvalidAction"},
                       "action_key must not be empty");
  }

  if (!m_manager.invokeAction(id, sanitizedKey, false)) {
    throw sdbus::Error(sdbus::Error::Name{"org.freedesktop.Notifications.Error.InvalidAction"},
                       "action_key is not available for this notification");
  }

  kLog.debug("notification action #{} key='{}'", id, sanitizedKey);
}

void NotificationService::emitActionInvoked(uint32_t id, const std::string& actionKey) {
  m_object->emitSignal("ActionInvoked").onInterface(k_interface).withArguments(id, actionKey);
}

std::tuple<std::string, std::string, std::string, std::string> NotificationService::onGetServerInformation() {
  return {"noctalia", "noctalia-dev", NOCTALIA_VERSION, "1.2"};
}
