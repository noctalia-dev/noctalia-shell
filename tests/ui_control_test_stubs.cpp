#include "core/deferred_call.h"
#include "core/ui_phase.h"
#include "render/text/glyph_registry.h"
#include "theme/builtin_palettes.h"

#include <functional>
#include <string>
#include <string_view>
#include <unordered_map>

UiPhase currentUiPhase() noexcept { return UiPhase::Idle; }
const char* uiPhaseName(UiPhase /*phase*/) noexcept { return "Idle"; }
void uiAssertSceneMutationAllowed(const char* /*operation*/) {}
void uiAssertNotRendering(const char* /*operation*/) {}

UiPhaseScope::UiPhaseScope(UiPhase /*phase*/) noexcept {}
UiPhaseScope::~UiPhaseScope() = default;

std::vector<std::function<void()>>& DeferredCall::queue() {
  static std::vector<std::function<void()>> q;
  return q;
}

void DeferredCall::callLater(std::function<void()> fn) {
  if (fn) {
    fn();
  }
}

int DeferredCall::wakeFd() { return -1; }
void DeferredCall::drainWakeFd() {}
std::vector<std::function<void()>> DeferredCall::takePending() { return {}; }

namespace GlyphRegistry {

  bool contains(std::string_view /*name*/) { return false; }
  char32_t lookup(std::string_view /*name*/) { return U'\0'; }

  const std::unordered_map<std::string, char32_t>& tablerIcons() {
    static const std::unordered_map<std::string, char32_t> icons;
    return icons;
  }

  const std::unordered_map<std::string, std::string_view>& aliases() {
    static const std::unordered_map<std::string, std::string_view> aliases;
    return aliases;
  }

} // namespace GlyphRegistry

namespace noctalia::theme {

  const BuiltinPalette* testPalette() {
    static const BuiltinPalette palette{.name = "Noctalia"};
    return &palette;
  }

  std::span<const BuiltinPalette> builtinPalettes() { return {testPalette(), 1}; }
  const BuiltinPalette* findBuiltinPalette(std::string_view /*name*/) { return testPalette(); }
  GeneratedPalette expandBuiltinPalette(const BuiltinPalette& /*palette*/) { return {}; }

} // namespace noctalia::theme
