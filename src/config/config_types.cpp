#include "config/config_types.h"

#include "core/log.h"
#include "util/string_utils.h"
#include "wayland/wayland_connection.h"
#include "wayland/wayland_seat.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cstddef>
#include <stdexcept>
#include <utility>
#include <xkbcommon/xkbcommon.h>

namespace {
  constexpr Logger kLog("config");

  IdleActionRequest commandIdleAction(std::string command) {
    if (command.empty()) {
      return {};
    }
    return IdleActionRequest{.kind = IdleActionKind::Command, .command = std::move(command)};
  }

  IdleActionRequest idleAction(IdleActionKind kind) { return IdleActionRequest{.kind = kind, .command = {}}; }

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

std::vector<ShortcutConfig> defaultControlCenterShortcuts() {
  return {
      {"wifi"}, {"bluetooth"}, {"caffeine"}, {"nightlight"}, {"notification"}, {"power_profile"},
  };
}

std::vector<SessionPanelActionConfig> defaultSessionPanelActions() {
  return {
      SessionPanelActionConfig{"lock", true, std::nullopt, std::nullopt, std::nullopt, false},
      SessionPanelActionConfig{"logout", true, std::nullopt, std::nullopt, std::nullopt, false},
      SessionPanelActionConfig{"reboot", true, std::nullopt, std::nullopt, std::nullopt, false},
      SessionPanelActionConfig{"shutdown", true, std::nullopt, std::nullopt, std::nullopt, true},
  };
}

std::vector<IdleBehaviorConfig> defaultIdleBehaviors() {
  return {
      IdleBehaviorConfig{
          .name = "lock",
          .enabled = false,
          .timeoutSeconds = 600,
          .action = "lock",
          .command = "",
          .resumeCommand = "",
      },
      IdleBehaviorConfig{
          .name = "screen-off",
          .enabled = false,
          .timeoutSeconds = 660,
          .action = "screen_off",
          .command = "",
          .resumeCommand = "",
      },
      IdleBehaviorConfig{
          .name = "suspend",
          .enabled = false,
          .timeoutSeconds = 900,
          .action = "suspend",
          .command = "",
          .resumeCommand = "",
          .lockBeforeSuspend = true,
      },
  };
}

float panelCardOpacityForTransparencyMode(PanelTransparencyMode mode, float panelBackgroundOpacity) noexcept {
  const float backgroundOpacity = std::clamp(panelBackgroundOpacity, 0.0f, 1.0f);
  switch (mode) {
  case PanelTransparencyMode::Solid:
    return 1.0f;
  case PanelTransparencyMode::Soft:
    return std::clamp(backgroundOpacity + 0.10f, 0.78f, 0.88f);
  case PanelTransparencyMode::Glass:
    return std::clamp(backgroundOpacity + 0.02f, 0.58f, 0.70f);
  }
  return 1.0f;
}

float detachedPanelBackgroundOpacityForTransparencyMode(PanelTransparencyMode mode) noexcept {
  switch (mode) {
  case PanelTransparencyMode::Solid:
    return 1.0f;
  case PanelTransparencyMode::Soft:
    return 0.90f;
  case PanelTransparencyMode::Glass:
    return 0.72f;
  }
  return 1.0f;
}

void inferIdleBehaviorActionFromLegacyFields(IdleBehaviorConfig& behavior) {
  if (!behavior.action.empty()) {
    return;
  }
  if (behavior.command == "noctalia:screen-lock") {
    behavior.action = "lock";
    return;
  }
  if (behavior.command == "noctalia:dpms-off") {
    behavior.action = "screen_off";
    return;
  }
  if (behavior.command == "noctalia:suspend") {
    behavior.action = "suspend";
    return;
  }
  behavior.action = "command";
}

ResolvedIdleBehavior resolveIdleBehaviorActions(const IdleBehaviorConfig& behavior) {
  IdleBehaviorConfig tmp = behavior;
  inferIdleBehaviorActionFromLegacyFields(tmp);
  const std::string& act = tmp.action;
  const auto resume = [&tmp](IdleActionRequest fallback) {
    return tmp.resumeCommand.empty() ? std::move(fallback) : commandIdleAction(tmp.resumeCommand);
  };

  if (act == "lock") {
    return {
        .idleAction = idleAction(IdleActionKind::Lock),
        .resumeAction = resume({}),
    };
  }
  if (act == "screen_off") {
    return {
        .idleAction = idleAction(IdleActionKind::ScreenOff),
        .resumeAction = resume(idleAction(IdleActionKind::ScreenOn)),
    };
  }
  if (act == "suspend") {
    return {
        .idleAction = IdleActionRequest{.kind = IdleActionKind::Suspend,
                                        .command = {},
                                        .lockBeforeSuspend = tmp.lockBeforeSuspend},
        .resumeAction = resume({}),
    };
  }
  return {
      .idleAction = commandIdleAction(behavior.command),
      .resumeAction = commandIdleAction(behavior.resumeCommand),
  };
}

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

  spec.padding = bar.widgetCapsulePadding;
  if (widget != nullptr && widget->hasSetting("capsule_padding")) {
    spec.padding = std::clamp(
        static_cast<float>(widget->getDouble("capsule_padding", static_cast<double>(spec.padding))), 0.0f, 48.0f);
  }
  if (bar.widgetCapsuleRadius.has_value()) {
    spec.radius = std::clamp(static_cast<float>(*bar.widgetCapsuleRadius), 0.0f, 80.0f);
  }
  if (widget != nullptr && widget->hasSetting("capsule_radius")) {
    spec.radius = std::clamp(
        static_cast<float>(widget->getDouble("capsule_radius", static_cast<double>(spec.radius.value_or(0.0f)))), 0.0f,
        80.0f);
  }
  spec.opacity = bar.widgetCapsuleOpacity;
  if (widget != nullptr && widget->hasSetting("capsule_opacity")) {
    spec.opacity = std::clamp(
        static_cast<float>(widget->getDouble("capsule_opacity", static_cast<double>(spec.opacity))), 0.0f, 1.0f);
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

namespace {
  std::string canonicalKeyName(std::string raw) {
    const std::string lower = StringUtils::toLower(raw);
    if (lower == "esc") {
      return "Escape";
    }
    if (lower == "enter") {
      return "Return";
    }
    if (lower == "kp_enter") {
      return "KP_Enter";
    }
    if (lower == "space" || lower == "spacebar") {
      return "space";
    }
    if (lower == "left") {
      return "Left";
    }
    if (lower == "right") {
      return "Right";
    }
    if (lower == "up") {
      return "Up";
    }
    if (lower == "down") {
      return "Down";
    }
    return raw;
  }
} // namespace

std::optional<KeyChord> parseKeyChordSpec(std::string_view rawSpec) {
  const std::string spec = StringUtils::trim(rawSpec);
  if (spec.empty()) {
    return std::nullopt;
  }

  std::vector<std::string> tokens;
  std::size_t start = 0;
  while (start <= spec.size()) {
    const std::size_t plus = spec.find('+', start);
    const std::size_t len = (plus == std::string::npos) ? (spec.size() - start) : (plus - start);
    const std::string token = StringUtils::trim(std::string_view(spec).substr(start, len));
    if (token.empty()) {
      return std::nullopt;
    }
    tokens.push_back(token);
    if (plus == std::string::npos) {
      break;
    }
    start = plus + 1;
  }

  if (tokens.empty()) {
    return std::nullopt;
  }

  std::uint32_t modifiers = 0;
  for (std::size_t i = 0; i + 1 < tokens.size(); ++i) {
    const std::string mod = StringUtils::toLower(tokens[i]);
    if (mod == "ctrl" || mod == "control" || mod == "ctl") {
      modifiers |= KeyMod::Ctrl;
    } else if (mod == "shift") {
      modifiers |= KeyMod::Shift;
    } else if (mod == "alt" || mod == "option") {
      modifiers |= KeyMod::Alt;
    } else if (mod == "super" || mod == "meta" || mod == "logo" || mod == "win" || mod == "mod4") {
      throw std::runtime_error("modifier \"super/windows\" is not allowed");
    } else {
      return std::nullopt;
    }
  }

  const std::string keyName = canonicalKeyName(tokens.back());
  const xkb_keysym_t sym = xkb_keysym_from_name(keyName.c_str(), XKB_KEYSYM_CASE_INSENSITIVE);
  if (sym == XKB_KEY_NoSymbol) {
    return std::nullopt;
  }

  return KeyChord{.sym = static_cast<std::uint32_t>(sym), .modifiers = modifiers};
}

namespace {
  std::string keysymName(std::uint32_t sym) {
    if (sym == 0) {
      return {};
    }
    std::array<char, 64> buf{};
    const int n = xkb_keysym_get_name(static_cast<xkb_keysym_t>(sym), buf.data(), buf.size());
    if (n <= 0) {
      return {};
    }
    return std::string(buf.data(), static_cast<std::size_t>(n));
  }
} // namespace

std::string keyChordToString(const KeyChord& chord) {
  const std::string keyName = keysymName(chord.sym);
  if (keyName.empty()) {
    return {};
  }
  std::string out;
  if ((chord.modifiers & KeyMod::Ctrl) != 0) {
    out += "Ctrl+";
  }
  if ((chord.modifiers & KeyMod::Alt) != 0) {
    out += "Alt+";
  }
  if ((chord.modifiers & KeyMod::Shift) != 0) {
    out += "Shift+";
  }
  out += keyName;
  return out;
}

std::string keyChordDisplayLabel(const KeyChord& chord) {
  if (chord.sym == 0) {
    return {};
  }

  std::string keyName;

  // Prefer the printable glyph over the raw XKB name (e.g. "udiaeresis" -> "Ü").
  const std::uint32_t cp = xkb_keysym_to_utf32(static_cast<xkb_keysym_t>(chord.sym));
  if (cp > 0x20 && cp != 0x7F) {
    std::array<char, 8> utf8Buf{};
    const int n = xkb_keysym_to_utf8(static_cast<xkb_keysym_t>(chord.sym), utf8Buf.data(), utf8Buf.size());
    if (n > 1) {
      keyName.assign(utf8Buf.data(), static_cast<std::size_t>(n - 1));
      if (keyName.size() == 1 && keyName[0] >= 'a' && keyName[0] <= 'z') {
        keyName[0] = static_cast<char>(keyName[0] - 0x20);
      }
    }
  }

  if (keyName.empty()) {
    keyName = keysymName(chord.sym);
    if (keyName.empty()) {
      return {};
    }
    if (keyName == "Return") {
      keyName = "Enter";
    } else if (keyName == "KP_Enter") {
      keyName = "Numpad Enter";
    } else if (keyName == "space") {
      keyName = "Space";
    } else if (keyName == "Prior") {
      keyName = "Page Up";
    } else if (keyName == "Next") {
      keyName = "Page Down";
    }
  }

  std::string out;
  const auto appendPart = [&](std::string_view part) {
    if (!out.empty()) {
      out += " + ";
    }
    out += part;
  };
  if ((chord.modifiers & KeyMod::Ctrl) != 0) {
    appendPart("Ctrl");
  }
  if ((chord.modifiers & KeyMod::Alt) != 0) {
    appendPart("Alt");
  }
  if ((chord.modifiers & KeyMod::Shift) != 0) {
    appendPart("Shift");
  }
  appendPart(keyName);
  return out;
}
