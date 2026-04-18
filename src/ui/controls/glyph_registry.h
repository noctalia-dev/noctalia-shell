#pragma once

#include <string_view>

// Hand-curated alias → codepoint map.
// To add a new icon, find its codepoint in assets/fonts/tabler-icons.json
// and add an entry here.
namespace GlyphRegistry {

  [[nodiscard]] char32_t lookup(std::string_view name);

} // namespace GlyphRegistry
