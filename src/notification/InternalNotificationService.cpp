#include "notification/InternalNotificationService.hpp"

InternalNotificationService::InternalNotificationService(NotificationManager& manager)
    : m_manager(manager) {}

uint32_t InternalNotificationService::notify(std::string app_name,
                                             std::string summary,
                                             std::string body,
                                             int32_t timeout,
                                             Urgency urgency,
                                             std::optional<std::string> icon,
                                             std::optional<std::string> category,
                                             std::optional<std::string> desktop_entry) {
    return m_manager.addInternal(std::move(app_name),
                                 std::move(summary),
                                 std::move(body),
                                 timeout,
                                 urgency,
                                 std::move(icon),
                                 std::move(category),
                                 std::move(desktop_entry));
}