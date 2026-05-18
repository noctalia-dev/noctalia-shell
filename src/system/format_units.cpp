#include "system/format_units.h"

#include <format>

namespace FormatUnits {
  namespace {

    constexpr double kMibPerGib = 1024.0;
    constexpr double kBytesPerGib = 1024.0 * 1024.0 * 1024.0;
    constexpr double kBytesPerKb = 1000.0;
    constexpr double kBytesPerMb = 1000.0 * 1000.0;
    constexpr double kBytesPerGb = 1000.0 * 1000.0 * 1000.0;

    [[nodiscard]] const char* separator(Spacing spacing) { return spacing == Spacing::Spaced ? " " : ""; }

  } // namespace

  std::string formatBinaryMib(std::uint64_t mib, Spacing spacing) {
    if (mib >= static_cast<std::uint64_t>(kMibPerGib)) {
      return formatBinaryMibAsGib(mib, spacing);
    }
    return std::format("{}{}MiB", mib, separator(spacing));
  }

  std::string formatBinaryMibAsGib(std::uint64_t mib, Spacing spacing) {
    return std::format("{:.1f}{}GiB", static_cast<double>(mib) / kMibPerGib, separator(spacing));
  }

  std::string formatBinaryMibUsageAsGib(std::uint64_t usedMib, std::uint64_t totalMib) {
    return std::format("{:.1f} / {:.1f} GiB", static_cast<double>(usedMib) / kMibPerGib,
                       static_cast<double>(totalMib) / kMibPerGib);
  }

  std::string formatBinaryBytesAsGib(std::uint64_t bytes, Spacing spacing) {
    return std::format("{:.1f}{}GiB", static_cast<double>(bytes) / kBytesPerGib, separator(spacing));
  }

  std::string formatDecimalBytesUsageAsGb(double usedBytes, double totalBytes) {
    return std::format("{:.1f} / {:.1f} GB", usedBytes / kBytesPerGb, totalBytes / kBytesPerGb);
  }

  std::string formatDecimalBytesPerSecond(double bytesPerSec, Spacing spacing) {
    if (bytesPerSec >= kBytesPerGb) {
      return std::format("{:.1f}{}GB/s", bytesPerSec / kBytesPerGb, separator(spacing));
    }
    if (bytesPerSec >= kBytesPerMb) {
      return std::format("{:.1f}{}MB/s", bytesPerSec / kBytesPerMb, separator(spacing));
    }
    if (bytesPerSec >= kBytesPerKb) {
      return std::format("{:.1f}{}kB/s", bytesPerSec / kBytesPerKb, separator(spacing));
    }
    return std::format("{:.0f}{}B/s", bytesPerSec, separator(spacing));
  }

} // namespace FormatUnits
