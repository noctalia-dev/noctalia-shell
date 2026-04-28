#pragma once

// Values follow shadcn/ui proportions scaled to 85% for native desktop feel.
// When porting a shadcn component, multiply its pixel values by 0.85.
namespace Style {

  inline constexpr int barThicknessDefault = 34;

  inline constexpr int animFast = 100;
  inline constexpr int animNormal = 200;
  inline constexpr int animSlow = 400;

  inline constexpr float radiusSm = 2.0f;
  inline constexpr float radiusMd = 5.0f;
  inline constexpr float radiusLg = 8.0f;
  inline constexpr float radiusXl = 12.0f;

  inline constexpr float borderWidth = 1.0f;

  inline constexpr float spaceXs = 4.0f;
  inline constexpr float spaceSm = 8.0f;
  inline constexpr float spaceMd = 12.0f;
  inline constexpr float spaceLg = 16.0f;

  // Default inner inset for bar widget capsules (logical px, before bar content scale).
  inline constexpr float barCapsulePadding = 6.0f;
  inline constexpr float barGlyphSize = 16.0f;

  inline constexpr float fontSizeCaption = 12.0f;
  inline constexpr float fontSizeBody = 14.0f;
  inline constexpr float fontSizeTitle = 16.0f;
  inline constexpr float fontSizeHeader = 20.0f;

  inline constexpr float controlHeightSm = 28.0f;
  inline constexpr float controlHeight = 32.0f;
  inline constexpr float controlHeightLg = 36.0f;
  inline constexpr float scrollWheelStep = 56.0f;

} // namespace Style
