pragma Singleton

import QtQuick
import Quickshell
import qs.Services.Power

Singleton {
  id: root

  // Font size
  readonly property real fontSizeXXS: 8
  readonly property real fontSizeXS: 9
  readonly property real fontSizeS: 10
  readonly property real fontSizeM: 11
  readonly property real fontSizeL: 13
  readonly property real fontSizeXL: 16
  readonly property real fontSizeXXL: 18
  readonly property real fontSizeXXXL: 24

  // Font weight
  readonly property int fontWeightRegular: 400
  readonly property int fontWeightMedium: 500
  readonly property int fontWeightSemiBold: 600
  readonly property int fontWeightBold: 700

  // Container Radii: major layout sections (sidebars, cards, content panels)
  readonly property int radiusXXS: Math.round(4 * Settings.data.general.radiusRatio)
  readonly property int radiusXS: Math.round(8 * Settings.data.general.radiusRatio)
  readonly property int radiusS: Math.round(12 * Settings.data.general.radiusRatio)
  readonly property int radiusM: Math.round(16 * Settings.data.general.radiusRatio)
  readonly property int radiusL: Math.round(20 * Settings.data.general.radiusRatio)

  // Input radii: interactive elements (buttons, toggles, text fields)
  readonly property int iRadiusXXS: Math.round(4 * Settings.data.general.iRadiusRatio)
  readonly property int iRadiusXS: Math.round(8 * Settings.data.general.iRadiusRatio)
  readonly property int iRadiusS: Math.round(12 * Settings.data.general.iRadiusRatio)
  readonly property int iRadiusM: Math.round(16 * Settings.data.general.iRadiusRatio)
  readonly property int iRadiusL: Math.round(20 * Settings.data.general.iRadiusRatio)

  readonly property int screenRadius: Math.round(20 * Settings.data.general.screenRadiusRatio)

  // Border
  readonly property int borderS: Math.max(1, Math.round(1 * uiScaleRatio))
  readonly property int borderM: Math.max(1, Math.round(2 * uiScaleRatio))
  readonly property int borderL: Math.max(1, Math.round(3 * uiScaleRatio))

  // Margins (for margins and spacing)
  readonly property int marginXXS: Math.round(2 * uiScaleRatio)
  readonly property int marginXS: Math.round(4 * uiScaleRatio)
  readonly property int marginS: Math.round(6 * uiScaleRatio)
  readonly property int marginM: Math.round(9 * uiScaleRatio)
  readonly property int marginL: Math.round(13 * uiScaleRatio)
  readonly property int marginXL: Math.round(18 * uiScaleRatio)

  // Opacity
  readonly property real opacityNone: 0.0
  readonly property real opacityLight: 0.25
  readonly property real opacityMedium: 0.5
  readonly property real opacityHeavy: 0.75
  readonly property real opacityAlmost: 0.95
  readonly property real opacityFull: 1.0

  // Shadows
  readonly property real shadowOpacity: 0.85
  readonly property real shadowBlur: 1.0
  readonly property int shadowBlurMax: 22
  readonly property real shadowHorizontalOffset: Settings.data.general.shadowOffsetX
  readonly property real shadowVerticalOffset: Settings.data.general.shadowOffsetY

  // Animation duration (ms)
  readonly property int animationFaster: (Settings.data.general.animationDisabled || PowerProfileService.noctaliaPerformanceMode) ? 0 : Math.round(75 / Settings.data.general.animationSpeed)
  readonly property int animationFast: (Settings.data.general.animationDisabled || PowerProfileService.noctaliaPerformanceMode) ? 0 : Math.round(150 / Settings.data.general.animationSpeed)
  readonly property int animationNormal: (Settings.data.general.animationDisabled || PowerProfileService.noctaliaPerformanceMode) ? 0 : Math.round(300 / Settings.data.general.animationSpeed)
  readonly property int animationSlow: (Settings.data.general.animationDisabled || PowerProfileService.noctaliaPerformanceMode) ? 0 : Math.round(450 / Settings.data.general.animationSpeed)
  readonly property int animationSlowest: (Settings.data.general.animationDisabled || PowerProfileService.noctaliaPerformanceMode) ? 0 : Math.round(750 / Settings.data.general.animationSpeed)

  // Delays
  readonly property int tooltipDelay: 300
  readonly property int tooltipDelayLong: 1200
  readonly property int pillDelay: 500

  // Widgets base size
  readonly property real baseWidgetSize: 33
  readonly property real sliderWidth: 200

  readonly property real uiScaleRatio: Settings.data.general.scaleRatio

  // Bar Height
  readonly property real barHeight: {
    let h;
    switch (Settings.data.bar.density) {
      case "mini":
      h = (Settings.data.bar.position === "left" || Settings.data.bar.position === "right") ? 23 : 21;
      break;
      case "compact":
      h = (Settings.data.bar.position === "left" || Settings.data.bar.position === "right") ? 27 : 25;
      break;
      case "comfortable":
      h = (Settings.data.bar.position === "left" || Settings.data.bar.position === "right") ? 39 : 37;
      break;
      case "spacious":
      h = (Settings.data.bar.position === "left" || Settings.data.bar.position === "right") ? 49 : 47;
      break;
      default:
      case "default":
      h = (Settings.data.bar.position === "left" || Settings.data.bar.position === "right") ? 33 : 31;
    }
    return toOdd(h);
  }

  // Capsule Height
  readonly property real capsuleHeight: {
    let h;
    switch (Settings.data.bar.density) {
      case "mini":
      h = Math.round(barHeight * 1.0);
      break;
      case "compact":
      h = Math.round(barHeight * 0.85);
      break;
      case "comfortable":
      h = Math.round(barHeight * 0.75);
      break;
      case "spacious":
      h = Math.round(barHeight * 0.65);
      break;
      default:
      h = Math.round(barHeight * 0.82);
      break;
    }
    return toOdd(h);
  }

  // The base/default font size for all texts in the bar
  readonly property real _barBaseFontSize: Math.max(1, (Style.barHeight / Style.capsuleHeight) * Style.fontSizeXXS)
  readonly property real barFontSize: (Settings.data.bar.position === "left" || Settings.data.bar.position === "right") ? _barBaseFontSize * 0.9 : _barBaseFontSize

  readonly property color capsuleColor: Settings.data.bar.showCapsule ? Qt.alpha(Color.mSurfaceVariant, Settings.data.bar.capsuleOpacity) : Color.transparent

  readonly property color capsuleBorderColor: Settings.data.bar.showOutline ? Color.mPrimary : Color.transparent
  readonly property int capsuleBorderWidth: Settings.data.bar.showOutline ? Style.borderS : 0

  readonly property color boxBorderColor: Settings.data.ui.boxBorderEnabled ? Color.mOutline : Color.transparent

  // Pixel-perfect utility for centering content without subpixel positioning
  function pixelAlignCenter(containerSize, contentSize) {
    return Math.round((containerSize - contentSize) / 2);
  }

  // Ensures a number is always odd (rounds down to nearest odd)
  function toOdd(n) {
    return Math.floor(n / 2) * 2 + 1;
  }

  // Ensures a number is always even (rounds down to nearest even)
  function toEven(n) {
    return Math.floor(n / 2) * 2;
  }
}
