#pragma once

#include "config/config_types.h"

#include <cstdint>
#include <utility>

namespace settings::popup_layout {

  [[nodiscard]] float preferredContentWidth(
      std::uint32_t parentWidth, float scale, float minLogical, float maxLogical, float parentFraction,
      float parentMarginLogical, const ShellConfig::ShadowConfig& shadow
  );

  [[nodiscard]] std::pair<std::uint32_t, std::uint32_t>
  surfaceSizeForContent(float contentWidth, float contentHeight, const ShellConfig::ShadowConfig& shadow);

} // namespace settings::popup_layout
