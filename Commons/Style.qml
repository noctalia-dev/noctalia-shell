pragma Singleton

import QtQuick
import Quickshell
import qs.Services.Power

Singleton {
  id: root


  /*
    Preset sizes for font, radii, ?
  */

  // Font size
  property real fontSizeXXS: 8
  property real fontSizeXS: 9
  property real fontSizeS: 10
  property real fontSizeM: 11
  property real fontSizeL: 13
  property real fontSizeXL: 16
  property real fontSizeXXL: 18
  property real fontSizeXXXL: 24

  // Font weight
  property int fontWeightRegular: 400
  property int fontWeightMedium: 500
  property int fontWeightSemiBold: 600
  property int fontWeightBold: 700

  // Radii
  property int radiusXXS: Math.round(4 * Settings.data.general.radiusRatio)
  property int radiusXS: Math.round(8 * Settings.data.general.radiusRatio)
  property int radiusS: Math.round(12 * Settings.data.general.radiusRatio)
  property int radiusM: Math.round(16 * Settings.data.general.radiusRatio)
  property int radiusL: Math.round(20 * Settings.data.general.radiusRatio)
  property int screenRadius: Math.round(20 * Settings.data.general.screenRadiusRatio)

  // Border
  property int borderS: Math.max(1, Math.round(1 * uiScaleRatio))
  property int borderM: Math.max(1, Math.round(2 * uiScaleRatio))
  property int borderL: Math.max(1, Math.round(3 * uiScaleRatio))

  // Margins (for margins and spacing)
  property int marginXXS: Math.round(2 * uiScaleRatio)
  property int marginXS: Math.round(4 * uiScaleRatio)
  property int marginS: Math.round(6 * uiScaleRatio)
  property int marginM: Math.round(9 * uiScaleRatio)
  property int marginL: Math.round(13 * uiScaleRatio)
  property int marginXL: Math.round(18 * uiScaleRatio)

  // Opacity
  property real opacityNone: 0.0
  property real opacityLight: 0.25
  property real opacityMedium: 0.5
  property real opacityHeavy: 0.75
  property real opacityAlmost: 0.95
  property real opacityFull: 1.0

  // Shadows
  property real shadowOpacity: 0.85
  property real shadowBlur: 1.0
  property int shadowBlurMax: 22
  property real shadowHorizontalOffset: Settings.data.general.shadowOffsetX
  property real shadowVerticalOffset: Settings.data.general.shadowOffsetY

  // Animation duration (ms)
  property int animationFaster: (Settings.data.general.animationDisabled || PowerProfileService.noctaliaPerformanceMode) ? 0 : Math.round(75 / Settings.data.general.animationSpeed)
  property int animationFast: (Settings.data.general.animationDisabled || PowerProfileService.noctaliaPerformanceMode) ? 0 : Math.round(150 / Settings.data.general.animationSpeed)
  property int animationNormal: (Settings.data.general.animationDisabled || PowerProfileService.noctaliaPerformanceMode) ? 0 : Math.round(300 / Settings.data.general.animationSpeed)
  property int animationSlow: (Settings.data.general.animationDisabled || PowerProfileService.noctaliaPerformanceMode) ? 0 : Math.round(450 / Settings.data.general.animationSpeed)
  property int animationSlowest: (Settings.data.general.animationDisabled || PowerProfileService.noctaliaPerformanceMode) ? 0 : Math.round(750 / Settings.data.general.animationSpeed)

  // Delays
  property int tooltipDelay: 300
  property int tooltipDelayLong: 1200
  property int pillDelay: 500

  // Widgets base size
  property real baseWidgetSize: 33
  property real sliderWidth: 200

  property real uiScaleRatio: Settings.data.general.scaleRatio

  // Bar Dimensions
  property real barHeight: {
    switch (Settings.data.bar.density) {
      case "mini":
      return (Settings.data.bar.position === "left" || Settings.data.bar.position === "right") ? 22 : 20
      case "compact":
      return (Settings.data.bar.position === "left" || Settings.data.bar.position === "right") ? 27 : 25
      case "comfortable":
      return (Settings.data.bar.position === "left" || Settings.data.bar.position === "right") ? 39 : 37
      default:

      case "default":
      return (Settings.data.bar.position === "left" || Settings.data.bar.position === "right") ? 33 : 31
    }
  }
  property real capsuleHeight: {
    switch (Settings.data.bar.density) {
      case "mini":
      return Math.round(barHeight * 1.0)
      case "compact":
      return Math.round(barHeight * 0.85)
      case "comfortable":
      return Math.round(barHeight * 0.73)
      default:

      case "default":
      return Math.round(barHeight * 0.82)
    }
  }
}
