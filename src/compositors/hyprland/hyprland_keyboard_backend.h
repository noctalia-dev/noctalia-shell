#pragma once

#include "compositors/keyboard_backend.h"

#include <optional>
#include <string>
#include <string_view>

class HyprlandKeyboardBackend {
public:
  explicit HyprlandKeyboardBackend(std::string_view compositorHint);

  [[nodiscard]] bool isAvailable() const noexcept;
  [[nodiscard]] bool cycleLayout() const;
  [[nodiscard]] std::optional<KeyboardLayoutState> layoutState() const;
  [[nodiscard]] std::optional<std::string> currentLayoutName() const;

private:
  bool m_enabled = false;
};
