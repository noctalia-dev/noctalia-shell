#pragma once

#include "noctalia_git_revision.h"

#include <string>
#include <string_view>

namespace noctalia::build_info {

  inline constexpr std::string_view version() noexcept { return NOCTALIA_VERSION; }

  inline constexpr std::string_view revision() noexcept { return NOCTALIA_GIT_REVISION; }

  inline std::string displayVersion() {
    std::string label = "v";
    label += version();

    constexpr std::string_view unknownRevision = "unknown";
    const std::string_view rev = revision();
    if (!rev.empty() && rev != unknownRevision) {
      label += " (";
      label += rev;
      label += ')';
    }
    return label;
  }

} // namespace noctalia::build_info
