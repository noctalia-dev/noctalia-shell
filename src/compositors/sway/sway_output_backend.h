#pragma once

#include <optional>
#include <string>
#include <string_view>

class SwayOutputBackend {
public:
  explicit SwayOutputBackend(std::string_view compositorHint);

  [[nodiscard]] bool isAvailable() const noexcept;
  [[nodiscard]] std::optional<std::string> focusedOutputName() const;

private:
  bool m_enabled = false;
};

namespace compositors::sway {

  [[nodiscard]] bool setOutputPower(bool on);

} // namespace compositors::sway
