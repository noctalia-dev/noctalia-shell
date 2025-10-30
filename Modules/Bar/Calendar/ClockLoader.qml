import QtQuick
import qs.Commons
import qs.Services
import Quickshell

Item {
  id: clockRoot
  property var now

  // Default colors
  property color backgroundColor: Color.mPrimary
  property color clockColor: Color.mOnPrimary

  function getRelativeLuminance(color) {
    return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
  }

  function getContrastRatio(color1, color2) {
    var L1 = getRelativeLuminance(color1)
    var L2 = getRelativeLuminance(color2)
    if (L1 > L2) {
      return (L1 + 0.05) / (L2 + 0.05)
    } else {
      return (L2 + 0.05) / (L1 + 0.05)
    }
  }

  property color secondHandColor: {
    var defaultColor = Color.mError
    var bestContrast = 1.0 // 1.0 is "no contrast"
    var bestColor = defaultColor
    var candidates = [Color.mSecondary, Color.mTertiary, Color.mError]

    const minContrast = 1.149

    for (var i = 0; i < candidates.length; i++) {
      var candidate = candidates[i]
      var contrastClock = getContrastRatio(candidate, clockColor)
      if (contrastClock < minContrast) {
        continue
      }
      var contrastBg = getContrastRatio(candidate, backgroundColor)
      if (contrastBg < minContrast) {
        continue
      }

      var currentWorstContrast = Math.min(contrastBg, contrastClock)

      if (currentWorstContrast > bestContrast) {
        bestContrast = currentWorstContrast
        bestColor = candidate
      }
    }

    return bestColor
  }

  property color progressColor: clockRoot.secondHandColor

  height: Math.round((Style.fontSizeXXXL * 1.9) / 2 * Style.uiScaleRatio) * 2
  width: clockRoot.height

  Loader {
    id: clockLoader
    anchors.fill: parent

    source: Settings.data.location.analogClockInCalendar ? "AnalogClock.qml" : "DigitalClock.qml"

    onLoaded: {
      item.now = Qt.binding(function () {
        return clockRoot.now
      })
      item.backgroundColor = Qt.binding(function () {
        return clockRoot.backgroundColor
      })
      item.clockColor = Qt.binding(function () {
        return clockRoot.clockColor
      })
      if (item.hasOwnProperty("secondHandColor")) {
        item.secondHandColor = Qt.binding(function () {
          return clockRoot.secondHandColor
        })
      }
      if (item.hasOwnProperty("progressColor")) {
        item.progressColor = Qt.binding(function () {
          return clockRoot.progressColor
        })
      }
    }
  }
}
