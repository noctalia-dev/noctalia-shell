#pragma once

#include "render/core/renderer.h"

#include <array>
#include <string_view>

namespace settings {

  struct FontWeightI18nOption {
    FontWeight weight;
    std::string_view labelKey;
  };

  inline constexpr std::array<FontWeightI18nOption, 12> kFontWeightOptions = {{
      {FontWeight::Thin, "settings.options.font-weight.thin"},
      {FontWeight::UltraLight, "settings.options.font-weight.ultra-light"},
      {FontWeight::Light, "settings.options.font-weight.light"},
      {FontWeight::SemiLight, "settings.options.font-weight.semi-light"},
      {FontWeight::Book, "settings.options.font-weight.book"},
      {FontWeight::Normal, "settings.options.font-weight.regular"},
      {FontWeight::Medium, "settings.options.font-weight.medium"},
      {FontWeight::SemiBold, "settings.options.font-weight.semi-bold"},
      {FontWeight::Bold, "settings.options.font-weight.bold"},
      {FontWeight::UltraBold, "settings.options.font-weight.ultra-bold"},
      {FontWeight::Heavy, "settings.options.font-weight.heavy"},
      {FontWeight::UltraHeavy, "settings.options.font-weight.ultra-heavy"},
  }};

} // namespace settings
