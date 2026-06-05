#pragma once

#include "notification.h"

#include <optional>
#include <string>
#include <string_view>
#include <unordered_set>
#include <vector>

struct NotificationFilterFields {
  std::string_view appName;
  std::optional<std::string_view> category;
  std::optional<std::string_view> desktopEntry;
};

[[nodiscard]] std::vector<std::string> normalizeNotificationBlacklist(std::vector<std::string> blacklist);

[[nodiscard]] bool
notificationMatchesBlacklist(const std::vector<std::string>& blacklist, const NotificationFilterFields& fields);

/// Empty result means all urgencies are allowed.
[[nodiscard]] std::unordered_set<Urgency> normalizeAllowedUrgencies(std::vector<std::string> values);

[[nodiscard]] bool urgencyIsAllowed(const std::unordered_set<Urgency>& allowed, Urgency urgency) noexcept;
