#pragma once

#include "notification/NotificationManager.h"

#include <cstdint>
#include <optional>
#include <string>

class InternalNotificationService {
public:
  explicit InternalNotificationService(NotificationManager& manager);

  uint32_t notify(std::string app_name, std::string summary, std::string body, int32_t timeout = 5000,
                  Urgency urgency = Urgency::Normal, std::optional<std::string> icon = std::nullopt,
                  std::optional<std::string> category = std::nullopt,
                  std::optional<std::string> desktop_entry = std::nullopt);

private:
  NotificationManager& m_manager;
};