#include "compositors/hyprland/hyprland_window_id.h"

#include <charconv>
#include <format>

namespace compositors::hyprland {

  std::string formatWindowAddress(const std::uint64_t address) { return std::format("{:x}", address); }

  std::string normalizeWindowId(const std::string_view value) {
    if (const auto parsed = parseWindowAddress(value); parsed.has_value()) {
      return formatWindowAddress(*parsed);
    }
    return {};
  }

  bool windowIdsEqual(const std::string_view lhs, const std::string_view rhs) {
    const auto left = normalizeWindowId(lhs);
    const auto right = normalizeWindowId(rhs);
    return !left.empty() && left == right;
  }

  std::optional<std::uint64_t> parseWindowAddress(const std::string_view value) {
    if (value.empty()) {
      return std::nullopt;
    }
    std::string_view digits = value;
    if (digits.starts_with("0x") || digits.starts_with("0X")) {
      digits = digits.substr(2);
    }
    if (digits.empty()) {
      return std::nullopt;
    }
    std::uint64_t address = 0;
    const auto* begin = digits.data();
    const auto* end = digits.data() + digits.size();
    const auto [ptr, ec] = std::from_chars(begin, end, address, 16);
    if (ec != std::errc{} || ptr != end) {
      return std::nullopt;
    }
    return address;
  }

} // namespace compositors::hyprland
