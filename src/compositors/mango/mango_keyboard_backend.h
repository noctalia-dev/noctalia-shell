#pragma once

#include "compositors/keyboard_backend.h"

#include <optional>
#include <string>

namespace compositors::mango {
  class MangoRuntime;
}

class MangoKeyboardBackend {
public:
  explicit MangoKeyboardBackend(compositors::mango::MangoRuntime& runtime);
  ~MangoKeyboardBackend() = default;

  MangoKeyboardBackend(const MangoKeyboardBackend&) = delete;
  MangoKeyboardBackend& operator=(const MangoKeyboardBackend&) = delete;
  MangoKeyboardBackend(MangoKeyboardBackend&&) = delete;
  MangoKeyboardBackend& operator=(MangoKeyboardBackend&&) = delete;

  [[nodiscard]] bool isAvailable() const noexcept;
  [[nodiscard]] bool cycleLayout() const;
  [[nodiscard]] std::optional<KeyboardLayoutState> layoutState() const;
  [[nodiscard]] std::optional<std::string> currentLayoutName() const;

private:
  compositors::mango::MangoRuntime& m_runtime;
};
