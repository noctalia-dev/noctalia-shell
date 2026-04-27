#include "compositors/compositor_detect.h"

#include "util/string_utils.h"

#include <cstdlib>
#include <string>

namespace compositors {

  namespace {

    [[nodiscard]] std::string buildEnvHint() {
      constexpr const char* vars[] = {"XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP", "DESKTOP_SESSION"};
      std::string hint;
      for (const char* var : vars) {
        const char* value = std::getenv(var);
        if (value == nullptr || value[0] == '\0') {
          continue;
        }
        if (!hint.empty()) {
          hint += ':';
        }
        hint += value;
      }
      return hint;
    }

    [[nodiscard]] CompositorKind detectImpl() {
      // Compositor-set socket env vars are the most reliable signal.
      if (const char* v = std::getenv("NIRI_SOCKET"); v != nullptr && v[0] != '\0') {
        return CompositorKind::Niri;
      }
      if (const char* v = std::getenv("HYPRLAND_INSTANCE_SIGNATURE"); v != nullptr && v[0] != '\0') {
        return CompositorKind::Hyprland;
      }
      if (const char* v = std::getenv("SWAYSOCK"); v != nullptr && v[0] != '\0') {
        return CompositorKind::Sway;
      }

      // Fall back to the desktop env hint (covers dwl-style compositors that don't expose a socket var).
      const std::string hint = buildEnvHint();
      if (StringUtils::containsInsensitive(hint, "niri")) {
        return CompositorKind::Niri;
      }
      if (StringUtils::containsInsensitive(hint, "hypr")) {
        return CompositorKind::Hyprland;
      }
      if (StringUtils::containsInsensitive(hint, "sway")) {
        return CompositorKind::Sway;
      }
      if (StringUtils::containsInsensitive(hint, "mango") || StringUtils::containsInsensitive(hint, "dwl")) {
        return CompositorKind::Mango;
      }
      return CompositorKind::Unknown;
    }

  } // namespace

  CompositorKind detect() {
    static const CompositorKind cached = detectImpl();
    return cached;
  }

  std::string_view name(CompositorKind kind) {
    switch (kind) {
    case CompositorKind::Niri:
      return "Niri";
    case CompositorKind::Hyprland:
      return "Hyprland";
    case CompositorKind::Sway:
      return "Sway";
    case CompositorKind::Mango:
      return "Mango";
    case CompositorKind::Unknown:
      return "Unknown";
    }
    return "Unknown";
  }

  std::string_view envHint() {
    static const std::string cached = buildEnvHint();
    return cached;
  }

} // namespace compositors
