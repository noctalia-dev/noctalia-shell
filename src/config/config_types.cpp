#include "config/config_types.h"

#include "core/log.h"
#include "util/string_utils.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <cctype>

namespace {
  constexpr Logger kLog("config");

  ColorSpec parseColorSpecString(const std::string& raw) {
    const std::string trimmed = StringUtils::trim(raw);
    Color fixed;
    if (tryParseHexColor(trimmed, fixed)) {
      return fixedColorSpec(fixed);
    }
    if (auto role = colorRoleFromToken(trimmed)) {
      return colorSpecFromRole(*role);
    }
    kLog.warn("unknown color role \"{}\", using surface_variant", raw);
    return colorSpecFromRole(ColorRole::SurfaceVariant);
  }

  std::optional<ColorSpec> optionalCapsuleBorder(const std::string& raw) {
    if (StringUtils::trim(raw).empty()) {
      return std::nullopt;
    }
    return parseColorSpecString(raw);
  }

} // namespace

std::string WidgetConfig::getString(const std::string& key, const std::string& fallback) const {
  auto it = settings.find(key);
  if (it == settings.end()) {
    return fallback;
  }
  if (const auto* v = std::get_if<std::string>(&it->second)) {
    return *v;
  }
  return fallback;
}

std::vector<std::string> WidgetConfig::getStringList(const std::string& key,
                                                     const std::vector<std::string>& fallback) const {
  auto it = settings.find(key);
  if (it == settings.end()) {
    return fallback;
  }
  if (const auto* v = std::get_if<std::vector<std::string>>(&it->second)) {
    return *v;
  }
  if (const auto* v = std::get_if<std::string>(&it->second)) {
    return {*v};
  }
  return fallback;
}

std::int64_t WidgetConfig::getInt(const std::string& key, std::int64_t fallback) const {
  auto it = settings.find(key);
  if (it == settings.end()) {
    return fallback;
  }
  if (const auto* v = std::get_if<std::int64_t>(&it->second)) {
    return *v;
  }
  return fallback;
}

double WidgetConfig::getDouble(const std::string& key, double fallback) const {
  auto it = settings.find(key);
  if (it == settings.end()) {
    return fallback;
  }
  if (const auto* v = std::get_if<double>(&it->second)) {
    return *v;
  }
  // Allow int -> double promotion.
  if (const auto* v = std::get_if<std::int64_t>(&it->second)) {
    return static_cast<double>(*v);
  }
  return fallback;
}

bool WidgetConfig::getBool(const std::string& key, bool fallback) const {
  auto it = settings.find(key);
  if (it == settings.end()) {
    return fallback;
  }
  if (const auto* v = std::get_if<bool>(&it->second)) {
    return *v;
  }
  return fallback;
}

bool WidgetConfig::hasSetting(const std::string& key) const { return settings.find(key) != settings.end(); }

WidgetBarCapsuleSpec resolveWidgetBarCapsuleSpec(const BarConfig& bar, const WidgetConfig* widget) {
  WidgetBarCapsuleSpec spec{};
  const bool widgetHasCapsuleKey = widget != nullptr && widget->hasSetting("capsule");
  const bool widgetHasFillKey = widget != nullptr && widget->hasSetting("capsule_fill");
  const bool widgetHasBorderKey = widget != nullptr && widget->hasSetting("capsule_border");

  if (widgetHasCapsuleKey) {
    spec.enabled = widget->getBool("capsule", false);
  } else {
    spec.enabled = bar.widgetCapsuleDefault;
  }
  if (!spec.enabled) {
    return spec;
  }

  if (widget != nullptr && widget->hasSetting("capsule_group")) {
    spec.group = StringUtils::trim(widget->getString("capsule_group", ""));
  }

  if (widgetHasFillKey) {
    spec.fill = parseColorSpecString(widget->getString("capsule_fill", ""));
  } else {
    spec.fill = bar.widgetCapsuleFill;
  }

  if (widgetHasBorderKey) {
    spec.border = optionalCapsuleBorder(widget->getString("capsule_border", ""));
  } else if (bar.widgetCapsuleBorderSpecified) {
    spec.border = bar.widgetCapsuleBorder;
  } else {
    spec.border = std::nullopt;
  }

  spec.padding = bar.widgetCapsulePadding;
  if (widget != nullptr && widget->hasSetting("capsule_padding")) {
    spec.padding = std::clamp(
        static_cast<float>(widget->getDouble("capsule_padding", static_cast<double>(spec.padding))), 0.0f, 48.0f);
  }
  spec.opacity = bar.widgetCapsuleOpacity;
  if (widget != nullptr && widget->hasSetting("capsule_opacity")) {
    spec.opacity = std::clamp(
        static_cast<float>(widget->getDouble("capsule_opacity", static_cast<double>(spec.opacity))), 0.0f, 1.0f);
  }

  if (widget != nullptr && widget->hasSetting("capsule_foreground")) {
    spec.foreground = parseColorSpecString(widget->getString("capsule_foreground", ""));
  } else if (bar.widgetCapsuleForeground.has_value()) {
    spec.foreground = bar.widgetCapsuleForeground;
  } else {
    spec.foreground = std::nullopt;
  }
  return spec;
}

ColorSpec colorSpecFromConfigString(const std::string& raw) { return parseColorSpecString(raw); }

std::optional<HookKind> hookKindFromKey(std::string_view key) { return enumFromKey(kHookKinds, key); }

std::string_view hookKindKey(HookKind kind) {
  const std::string_view key = enumToKey(kHookKinds, kind);
  return key.empty() ? "unknown" : key;
}

bool outputMatchesSelector(const std::string& match, const WaylandOutput& output) {
  // Exact connector name match.
  if (!output.connectorName.empty() && match == output.connectorName) {
    return true;
  }

  // Word-boundary substring match on description. A bare substring search would
  // let "DP-1" match "eDP-1" inside descriptions like "BOE 0x0BCA eDP-1".
  if (!output.description.empty()) {
    std::size_t pos = 0;
    while ((pos = output.description.find(match, pos)) != std::string::npos) {
      const bool startOk = (pos == 0 || std::isspace(static_cast<unsigned char>(output.description[pos - 1])) != 0);
      const bool endOk = (pos + match.size() == output.description.size() ||
                          std::isspace(static_cast<unsigned char>(output.description[pos + match.size()])) != 0);
      if (startOk && endOk) {
        return true;
      }
      ++pos;
    }
  }
  return false;
}
