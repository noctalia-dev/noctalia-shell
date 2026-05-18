#pragma once

#include "config/config_types.h"

#include <array>
#include <cstdint>
#include <functional>
#include <optional>

/// Global keybind matchers for UI controls. Set once at application startup from ConfigService.
namespace KeybindMatcher {

  using Matcher = std::function<bool(std::uint32_t sym, std::uint32_t modifiers)>;

  void setMatcher(KeybindAction action, Matcher matcher);
  bool matches(KeybindAction action, std::uint32_t sym, std::uint32_t modifiers);

} // namespace KeybindMatcher
