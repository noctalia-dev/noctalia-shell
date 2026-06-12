#pragma once

#include <cstdint>

namespace noctalia::config {

  inline constexpr std::int64_t kClipboardHistoryMinEntries = 10;
  inline constexpr std::int64_t kClipboardHistoryDefaultEntries = 100;
  inline constexpr std::int64_t kClipboardHistoryMaxEntries = 10000;
  inline constexpr std::int64_t kClipboardHistoryStepEntries = 10;

} // namespace noctalia::config
