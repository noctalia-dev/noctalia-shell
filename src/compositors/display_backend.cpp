#include "compositors/display_backend.h"

#include "compositors/compositor_detect.h"
#include "compositors/compositor_runtime.h"
#include "compositors/hyprland/hyprland_display_backend.h"
#include "compositors/niri/niri_display_backend.h"
#include "compositors/sway/sway_display_backend.h"
#include "compositors/wlr_display_backend.h"
#include "core/process/process.h"

#include <cstdio>

namespace compositors::display {

  namespace {

    [[nodiscard]] bool wlrRandrWorks() {
      if (!process::commandExists("wlr-randr")) {
        return false;
      }
      return static_cast<bool>(process::runSync({"wlr-randr", "--json"}));
    }

  } // namespace

  std::unique_ptr<DisplayBackend> createDisplayBackend(CompositorRuntimeRegistry& runtimeRegistry) {
    switch (compositors::detect()) {
    case compositors::CompositorKind::Hyprland:
      if (process::commandExists("hyprctl")) {
        return std::make_unique<HyprlandDisplayBackend>();
      }
      break;
    case compositors::CompositorKind::Niri:
      if (process::commandExists("niri")) {
        return std::make_unique<NiriDisplayBackend>();
      }
      break;
    case compositors::CompositorKind::Sway:
      if (runtimeRegistry.sway().hasOutputCommand()) {
        return std::make_unique<SwayDisplayBackend>(runtimeRegistry.sway());
      }
      break;
    case compositors::CompositorKind::Mango:
    case compositors::CompositorKind::Labwc:
    case compositors::CompositorKind::Triad:
    case compositors::CompositorKind::Dwl:
    case compositors::CompositorKind::Kde:
    case compositors::CompositorKind::Umbriel:
    case compositors::CompositorKind::Unknown:
      break;
    }
    if (wlrRandrWorks()) {
      return std::make_unique<WlrDisplayBackend>(false);
    }
    return std::make_unique<WlrDisplayBackend>(true);
  }

  std::string_view transformToName(std::string_view transform) {
    if (transform == "90")
      return "90";
    if (transform == "180")
      return "180";
    if (transform == "270")
      return "270";
    if (transform == "Flipped")
      return "flipped";
    if (transform == "Flipped90")
      return "flipped-90";
    if (transform == "Flipped180")
      return "flipped-180";
    if (transform == "Flipped270")
      return "flipped-270";
    return "normal";
  }

  std::string transformFromName(std::string_view name) {
    if (name == "normal")
      return "Normal";
    if (name == "90")
      return "90";
    if (name == "180")
      return "180";
    if (name == "270")
      return "270";
    if (name == "flipped")
      return "Flipped";
    if (name == "flipped-90")
      return "Flipped90";
    if (name == "flipped-180")
      return "Flipped180";
    if (name == "flipped-270")
      return "Flipped270";
    return "Normal";
  }

  std::string transformFromCode(int code) {
    switch (code) {
    case 1:
      return "90";
    case 2:
      return "180";
    case 3:
      return "270";
    case 4:
      return "Flipped";
    case 5:
      return "Flipped90";
    case 6:
      return "Flipped180";
    case 7:
      return "Flipped270";
    default:
      return "Normal";
    }
  }

  int transformToCode(std::string_view transform) {
    if (transform == "90")
      return 1;
    if (transform == "180")
      return 2;
    if (transform == "270")
      return 3;
    if (transform == "Flipped")
      return 4;
    if (transform == "Flipped90")
      return 5;
    if (transform == "Flipped180")
      return 6;
    if (transform == "Flipped270")
      return 7;
    return 0;
  }

  std::string swayModeStr(std::string_view modeStr) {
    const std::string raw(modeStr);
    if (raw.empty()) {
      return "preferred";
    }
    const auto at = raw.find('@');
    if (at == std::string::npos) {
      return raw;
    }
    const char* begin = raw.data() + at + 1;
    char* end = nullptr;
    const double hz = std::strtod(begin, &end);
    if (end == begin || hz <= 0.0) {
      return raw;
    }
    char buffer[32];
    std::snprintf(buffer, sizeof(buffer), "%.3f", hz);
    return raw.substr(0, at + 1) + buffer + "Hz";
  }

  std::string formatRateHz(int refreshMhz) {
    char buffer[32];
    std::snprintf(buffer, sizeof(buffer), "%.3f", refreshMhz / 1000.0);
    return buffer;
  }

  bool rotatedTransform(std::string_view transform) {
    return transform == "90" || transform == "270" || transform == "Flipped90" || transform == "Flipped270";
  }

} // namespace compositors::display
