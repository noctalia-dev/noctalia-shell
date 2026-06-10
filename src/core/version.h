#pragma once

#include <array>
#include <cstdint>
#include <string_view>

namespace noctalia::version {

  // Parse up to three dotted numeric components (major.minor.patch). Any
  // pre-release / build suffix (`-rc1`, `+meta`) is ignored — comparison is on
  // the release triple only. Missing components are 0; non-numeric input yields 0.
  [[nodiscard]] inline std::array<std::uint32_t, 3> parseTriple(std::string_view v) {
    std::array<std::uint32_t, 3> out{0, 0, 0};
    std::size_t component = 0;
    std::uint32_t acc = 0;
    bool sawDigit = false;
    for (std::size_t i = 0; i <= v.size() && component < out.size(); ++i) {
      const char c = i < v.size() ? v[i] : '.';
      if (c >= '0' && c <= '9') {
        acc = acc * 10 + static_cast<std::uint32_t>(c - '0');
        sawDigit = true;
        continue;
      }
      if (c == '.') {
        out[component++] = acc;
        acc = 0;
        sawDigit = false;
        continue;
      }
      // Hit a pre-release / build separator (or junk): stop at this component.
      out[component] = sawDigit ? acc : out[component];
      break;
    }
    return out;
  }

  // -1 if a < b, 0 if equal, +1 if a > b (release triple only).
  [[nodiscard]] inline int compare(std::string_view a, std::string_view b) {
    const auto lhs = parseTriple(a);
    const auto rhs = parseTriple(b);
    for (std::size_t i = 0; i < lhs.size(); ++i) {
      if (lhs[i] != rhs[i]) {
        return lhs[i] < rhs[i] ? -1 : 1;
      }
    }
    return 0;
  }

  // True when `running` satisfies a `>= required` floor (the `min_noctalia` gate).
  [[nodiscard]] inline bool atLeast(std::string_view running, std::string_view required) {
    return compare(running, required) >= 0;
  }

} // namespace noctalia::version
