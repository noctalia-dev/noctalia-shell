#pragma once

// Values follow shadcn/ui proportions scaled to 85% for native desktop feel.
// When porting a shadcn component, multiply its pixel values by 0.85.
namespace Style {

inline constexpr int barHeightDefault = 34;

inline constexpr int radiusSm = 2;
inline constexpr int radiusMd = 5;
inline constexpr int radiusLg = 8;
inline constexpr int radiusXl = 12;
inline constexpr int radiusFull = 9999;

inline constexpr int borderWidth = 1;

inline constexpr int spaceXs = 4;
inline constexpr int spaceSm = 8;
inline constexpr int spaceMd = 12;
inline constexpr int spaceLg = 16;

inline constexpr int paddingV = spaceMd / 2;
inline constexpr int paddingH = spaceMd;

inline constexpr int controlHeightSm = 28;
inline constexpr int controlHeight = 32;
inline constexpr int controlHeightLg = 36;

inline constexpr int fontSizeCaption = 12;
inline constexpr int fontSizeBody = 14;
inline constexpr int fontSizeTitle = 16;

inline constexpr int animFast = 100;
inline constexpr int animNormal = 200;
inline constexpr int animSlow = 400;

} // namespace Style
