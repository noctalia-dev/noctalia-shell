#pragma once

#include <cstdint>
#include <string>

namespace FormatUnits {

  [[nodiscard]] std::string formatBinaryMib(std::uint64_t mib);
  [[nodiscard]] std::string formatBinaryMibAsGib(std::uint64_t mib);
  [[nodiscard]] std::string formatBinaryMibUsageAsGib(std::uint64_t usedMib, std::uint64_t totalMib);
  [[nodiscard]] std::string formatBinaryBytesAsGib(std::uint64_t bytes);
  [[nodiscard]] std::string formatDecimalBytesUsage(double usedBytes, double totalBytes);
  [[nodiscard]] std::string formatDecimalBytesAsGb(double bytes);
  [[nodiscard]] std::string formatDecimalBytesPerSecond(double bytesPerSec);

} // namespace FormatUnits
