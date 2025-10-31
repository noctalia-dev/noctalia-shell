import QtQuick
import qs.Commons
import qs.Services
import Quickshell
import "../../../Helpers/ColorsConvert.js" as ColorsConvert

Item {
  id: clockRoot
  property var now

  // Default colors
  property color backgroundColor: Color.mPrimary
  property color clockColor: Color.mOnPrimary

  property color secondHandColor: {
    var defaultColor = Color.mError
    var bestContrast = 1.0 // 1.0 is "no contrast"
    var bestColor = defaultColor
    var candidates = [Color.mSecondary, Color.mTertiary, Color.mError]

    const minContrast = 1.149

    for (var i = 0; i < candidates.length; i++) {
      var candidate = candidates[i]
      var contrastClock = ColorsConvert.getContrastRatio(candidate.toString(), clockColor.toString())
      if (contrastClock < minContrast) {
        continue
      }
      var contrastBg = ColorsConvert.getContrastRatio(candidate.toString(), backgroundColor.toString())
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
