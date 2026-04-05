#pragma once

// Values follow shadcn/ui proportions scaled to 85% for native desktop feel.
// When porting a shadcn component, multiply its pixel values by 0.85.
namespace Style {

inline constexpr float radiusSm = 2.0f;
inline constexpr float radiusMd = 5.0f;
inline constexpr float radiusLg = 8.0f;
inline constexpr float radiusFull = 9999.0f;

inline constexpr float borderWidth = 1.0f;

inline constexpr float spaceXs = 4.0f;
inline constexpr float spaceSm = 8.0f;
inline constexpr float spaceMd = 12.0f;
inline constexpr float spaceLg = 16.0f;

inline constexpr float paddingV = spaceMd * 0.5;
inline constexpr float paddingH = spaceMd;

inline constexpr float controlHeightSm = 28.0f;
inline constexpr float controlHeight = 32.0f;
inline constexpr float controlHeightLg = 36.0f;

inline constexpr float fontSizeCaption = 11.0f;
inline constexpr float fontSizeBody = 13.0f;
inline constexpr float fontSizeTitle = 16.0f;

inline constexpr float animFast = 100.0f;
inline constexpr float animNormal = 200.0f;
inline constexpr float animSlow = 400.0f;

} // namespace Style
