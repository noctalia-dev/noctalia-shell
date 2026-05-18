#include "ui/controls/keybind_matcher.h"

#include <xkbcommon/xkbcommon-keysyms.h>

namespace {

  std::array<std::optional<KeybindMatcher::Matcher>, 6> g_matchers{};

} // namespace

namespace KeybindMatcher {

  bool isPrintableKey(std::uint32_t sym) {
    if (sym >= XKB_KEY_a && sym <= XKB_KEY_z) {
      return true;
    }
    if (sym >= XKB_KEY_A && sym <= XKB_KEY_Z) {
      return true;
    }
    if (sym >= XKB_KEY_0 && sym <= XKB_KEY_9) {
      return true;
    }
    switch (sym) {
    case XKB_KEY_space:
    case XKB_KEY_exclam:
    case XKB_KEY_quotedbl:
    case XKB_KEY_numbersign:
    case XKB_KEY_dollar:
    case XKB_KEY_percent:
    case XKB_KEY_ampersand:
    case XKB_KEY_apostrophe:
    case XKB_KEY_parenleft:
    case XKB_KEY_parenright:
    case XKB_KEY_asterisk:
    case XKB_KEY_plus:
    case XKB_KEY_comma:
    case XKB_KEY_minus:
    case XKB_KEY_period:
    case XKB_KEY_slash:
    case XKB_KEY_colon:
    case XKB_KEY_semicolon:
    case XKB_KEY_less:
    case XKB_KEY_equal:
    case XKB_KEY_greater:
    case XKB_KEY_question:
    case XKB_KEY_at:
    case XKB_KEY_bracketleft:
    case XKB_KEY_backslash:
    case XKB_KEY_bracketright:
    case XKB_KEY_asciicircum:
    case XKB_KEY_underscore:
    case XKB_KEY_grave:
    case XKB_KEY_braceleft:
    case XKB_KEY_bar:
    case XKB_KEY_braceright:
    case XKB_KEY_asciitilde:
      return true;
    default:
      return false;
    }
  }

  void setMatcher(KeybindAction action, Matcher matcher) {
    auto idx = static_cast<std::size_t>(action);
    if (idx < g_matchers.size()) {
      g_matchers[idx] = std::move(matcher);
    }
  }

  bool matches(KeybindAction action, std::uint32_t sym, std::uint32_t modifiers) {
    if (isPrintableKey(sym) && modifiers == 0) {
      return false;
    }
    auto idx = static_cast<std::size_t>(action);
    if (idx < g_matchers.size() && g_matchers[idx]) {
      return (*g_matchers[idx])(sym, modifiers);
    }
    return false;
  }

} // namespace KeybindMatcher
