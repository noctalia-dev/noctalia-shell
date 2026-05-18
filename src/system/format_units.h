#pragma once

#include <cstdint>
#include <string>

namespace FormatUnits {

  enum class Spacing { Spaced, Compact };

  [[nodiscard]] std::string formatBinaryMib(std::uint64_t mib, Spacing spacing = Spacing::Spaced);
  [[nodiscard]] std::string formatBinaryMibAsGib(std::uint64_t mib, Spacing spacing = Spacing::Spaced);
  [[nodiscard]] std::string formatBinaryMibUsageAsGib(std::uint64_t usedMib, std::uint64_t totalMib);
  [[nodiscard]] std::string formatBinaryBytesAsGib(std::uint64_t bytes, Spacing spacing = Spacing::Spaced);
  [[nodiscard]] std::string formatDecimalBytesUsageAsGb(double usedBytes, double totalBytes);
  [[nodiscard]] std::string formatDecimalBytesPerSecond(double bytesPerSec, Spacing spacing = Spacing::Spaced);

} // namespace FormatUnits
