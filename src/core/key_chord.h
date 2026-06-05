#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

struct KeyChord {
  std::uint32_t sym = 0;       // XKB keysym
  std::uint32_t modifiers = 0; // KeyMod bitmask

  bool operator==(const KeyChord&) const = default;
};

// Throws std::runtime_error if spec contains a Super-family modifier.
// Bare printable keys (e.g. "1", "a") are accepted — UI-level policy is
// enforced by KeybindRecorder's ModifierPolicy, not here.
[[nodiscard]] std::optional<KeyChord> parseKeyChordSpec(std::string_view spec);
[[nodiscard]] std::string keyChordToString(const KeyChord& chord);
[[nodiscard]] std::string keyChordDisplayLabel(const KeyChord& chord);
[[nodiscard]] bool keyChordMatches(const KeyChord& chord, std::uint32_t sym, std::uint32_t modifiers) noexcept;
[[nodiscard]] bool isPrintableKey(std::uint32_t sym);
