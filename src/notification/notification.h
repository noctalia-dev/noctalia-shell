#pragma once

#include <chrono>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

enum class Urgency : uint8_t {
  Low = 0,
  Normal = 1,
  Critical = 2,
};

// org.freedesktop.Notifications close reason codes
enum class CloseReason : uint32_t {
  Expired = 1,
  Dismissed = 2,
  ClosedByCall = 3,
};

enum class NotificationOrigin : uint8_t {
  External = 0,
  Internal = 1,
};

using Clock = std::chrono::steady_clock;
using TimePoint = Clock::time_point;

struct Notification {
  uint32_t id;
  NotificationOrigin origin;
  std::string appName;
  std::string summary;
  std::string body;
  int32_t timeout;
  Urgency urgency;
  std::vector<std::string> actions; // pairs: [key, label, key, label, ...]
  std::optional<std::string> icon;
  std::optional<std::string> category;
  std::optional<std::string> desktopEntry;
  std::optional<TimePoint> expiryTime; // absent = never expires
};
