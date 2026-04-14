#pragma once

#include "compositors/keyboard_backend.h"

#include <optional>
#include <string>
#include <string_view>

class SwayKeyboardBackend {
public:
  explicit SwayKeyboardBackend(std::string_view compositorHint);

  [[nodiscard]] bool isAvailable() const noexcept;
  [[nodiscard]] bool cycleLayout() const;
  [[nodiscard]] std::optional<KeyboardLayoutState> layoutState() const;
  [[nodiscard]] std::optional<std::string> currentLayoutName() const;

private:
  bool m_enabled = false;
  std::string m_msgCommand;
};
