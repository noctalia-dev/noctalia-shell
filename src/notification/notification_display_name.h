#pragma once

#include "notification/notification.h"

#include <string>

// Best-effort human-readable app label for notification UI (toast, history, control center).
[[nodiscard]] std::string notificationDisplayAppName(const Notification& notification);
