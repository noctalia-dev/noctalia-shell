#pragma once

#include <string>
#include <string_view>
#include <unordered_map>

// Glyph names resolve in this order:
// 1. Explicit codepoint literals such as U+F123 or 0xF123.
// 2. Hand-curated Noctalia aliases from glyph_registry.cpp.
// 3. Native Tabler icon names from assets/fonts/tabler.json.
namespace GlyphRegistry {

  [[nodiscard]] bool contains(std::string_view name);
  [[nodiscard]] char32_t lookup(std::string_view name);

  // Full Tabler icon catalog (loaded from assets/fonts/tabler.json on first registry use).
  [[nodiscard]] const std::unordered_map<std::string, char32_t>& tablerIcons();
  // Hand-curated Noctalia alias -> native Tabler icon name map.
  [[nodiscard]] const std::unordered_map<std::string, std::string_view>& aliases();

} // namespace GlyphRegistry
