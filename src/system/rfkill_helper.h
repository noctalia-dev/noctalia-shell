#pragma once

#include <cstdint>
#include <string>
#include <string_view>

enum class RfkillDeviceType : std::uint8_t {
  Bluetooth,
  Wlan,
};

struct RfkillSwitchResult {
  bool success = false;
  bool hardBlocked = false;
  std::string detail;
};

/// Clears or sets the rfkill soft block for the first switch of the given type.
[[nodiscard]] RfkillSwitchResult setRfkillSoftBlocked(RfkillDeviceType type, bool softBlocked);

/// Clears or sets rfkill soft block for the WLAN switch tied to a network interface (e.g. wlan0).
[[nodiscard]] RfkillSwitchResult setRfkillSoftBlockedForNetInterface(std::string_view ifname, bool softBlocked);

/// True when a switch of this type exists and is soft-blocked.
[[nodiscard]] bool isRfkillSoftBlocked(RfkillDeviceType type);

/// True when a switch of this type exists and is hard-blocked.
[[nodiscard]] bool isRfkillHardBlocked(RfkillDeviceType type);
