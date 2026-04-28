#include "compositors/hyprland/hyprland_output_backend.h"

#include "core/process.h"

namespace compositors::hyprland {

  bool setOutputPower(bool on) { return process::runAsync({"hyprctl", "dispatch", "dpms", on ? "on" : "off"}); }

} // namespace compositors::hyprland
