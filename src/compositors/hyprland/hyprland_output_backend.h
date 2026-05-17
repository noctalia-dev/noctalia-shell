#pragma once

#include <optional>
#include <string>

namespace compositors::hyprland {
  class HyprlandRuntime;
} // namespace compositors::hyprland

class HyprlandOutputBackend {
public:
  explicit HyprlandOutputBackend(compositors::hyprland::HyprlandRuntime& runtime);
  [[nodiscard]] std::optional<std::string> focusedOutputName() const;

private:
  compositors::hyprland::HyprlandRuntime& m_runtime;
};

namespace compositors::hyprland {

  [[nodiscard]] bool setOutputPower(HyprlandRuntime& runtime, bool on);

} // namespace compositors::hyprland
