#pragma once

#include <string_view>

// Glyph names resolve in this order:
// 1. Hand-curated Noctalia aliases from glyph_registry.cpp.
// 2. Explicit codepoint literals such as U+F123 or 0xF123.
// 3. Native Tabler icon names from assets/fonts/tabler.json.
namespace GlyphRegistry {

  [[nodiscard]] bool contains(std::string_view name);
  [[nodiscard]] char32_t lookup(std::string_view name);

} // namespace GlyphRegistry
