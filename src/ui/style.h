#pragma once

namespace Style {

  inline constexpr int barThicknessDefault = 34;

  inline constexpr int animFast = 100;
  inline constexpr int animNormal = 200;
  inline constexpr int animSlow = 400;

  inline constexpr float radiusSm = 4.0f;
  inline constexpr float radiusMd = 8.0f;
  inline constexpr float radiusLg = 12.0f;
  inline constexpr float radiusXl = 16.0f;

  inline constexpr float borderWidth = 1.0f;

  inline constexpr float spaceXs = 4.0f;
  inline constexpr float spaceSm = 8.0f;
  inline constexpr float spaceMd = 12.0f;
  inline constexpr float spaceLg = 16.0f;

  inline constexpr float cardPadding = 14.0f;
  inline constexpr float panelPadding = 14.0f;

  // Default inner inset for bar widget capsules (logical px, before bar content scale).
  inline constexpr float barCapsulePadding = 6.0f;
  inline constexpr float barGlyphSize = 16.0f;
  inline constexpr float barIconSize = 16.0f;

  inline constexpr float fontSizeMini = 11.0f;
  inline constexpr float fontSizeCaption = 13.0f;
  inline constexpr float fontSizeBody = 14.0f;
  inline constexpr float fontSizeTitle = 16.0f;
  inline constexpr float fontSizeHeader = 20.0f;

  inline constexpr float controlHeightSm = 32.0f;
  inline constexpr float controlHeight = 38.0f;
  inline constexpr float controlHeightLg = 44.0f;
  inline constexpr float scrollWheelStep = 56.0f;

  // Toggle preset geometry. Track height = thumb + 2 * inset; track width = thumb + 2 * inset + travel.
  inline constexpr float toggleThumbSizeSm = 14.0f;
  inline constexpr float toggleInsetSm = 2.0f;
  inline constexpr float toggleTravelSm = 12.0f;
  inline constexpr float toggleThumbSizeMd = 18.0f;
  inline constexpr float toggleInsetMd = 3.0f;
  inline constexpr float toggleTravelMd = 16.0f;
  inline constexpr float toggleThumbSizeLg = 22.0f;
  inline constexpr float toggleInsetLg = 4.0f;
  inline constexpr float toggleTravelLg = 20.0f;

  // Slider geometry.
  inline constexpr float sliderDefaultWidth = 180.0f;
  inline constexpr float sliderTrackHeight = 8.0f;
  inline constexpr float sliderThumbSize = 18.0f;
  inline constexpr float sliderHorizontalPadding = 2.0f;

} // namespace Style
