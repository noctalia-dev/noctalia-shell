#pragma once

#include <string>
#include <string_view>
#include <unordered_map>

// Glyph names resolve in this order:
// 1. Hand-curated Noctalia aliases from glyph_registry.cpp.
// 2. Explicit codepoint literals such as U+F123 or 0xF123.
// 3. Native Tabler icon names from assets/fonts/tabler.json.
namespace GlyphRegistry {

  [[nodiscard]] bool contains(std::string_view name);
  [[nodiscard]] char32_t lookup(std::string_view name);

  // Full Tabler icon catalog (loaded from assets/fonts/tabler.json on first use).
  [[nodiscard]] const std::unordered_map<std::string, char32_t>& tablerIcons();
  // Hand-curated Noctalia aliases.
  [[nodiscard]] const std::unordered_map<std::string, char32_t>& aliases();

} // namespace GlyphRegistry
