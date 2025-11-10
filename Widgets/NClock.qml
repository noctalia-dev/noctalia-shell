import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import Quickshell
import "../Helpers/ColorsConvert.js" as ColorsConvert

Item {
  id: root

  property var now: Time.now

  // Style: "analog" or "digital"
  property string clockStyle: "analog"

  // Color properties
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

  property color progressColor: root.secondHandColor

  height: Math.round((Style.fontSizeXXXL * 1.9) / 2 * Style.uiScaleRatio) * 2
  width: root.height

  Loader {
    id: clockLoader
    anchors.fill: parent

    sourceComponent: root.clockStyle === "analog" ? analogClockComponent : digitalClockComponent

    onLoaded: {
      item.now = Qt.binding(function () {
        return root.now
      })
      item.backgroundColor = Qt.binding(function () {
        return root.backgroundColor
      })
      item.clockColor = Qt.binding(function () {
        return root.clockColor
      })
      if (item.hasOwnProperty("secondHandColor")) {
        item.secondHandColor = Qt.binding(function () {
          return root.secondHandColor
        })
      }
      if (item.hasOwnProperty("progressColor")) {
        item.progressColor = Qt.binding(function () {
          return root.progressColor
        })
      }
    }
  }

  // Analog Clock Component
  component NClockAnalog: Item {
    property var now
    property color backgroundColor: Color.mPrimary
    property color clockColor: Color.mOnPrimary
    property color secondHandColor: Color.mError
    anchors.fill: parent

    Canvas {
      id: clockCanvas
      anchors.fill: parent

      Connections {
        target: Time
        function onNowChanged() {
          clockCanvas.requestPaint()
        }
      }

      onPaint: {
        var currentTime = Time.now
        var hours = currentTime.getHours()
        var minutes = currentTime.getMinutes()
        var seconds = currentTime.getSeconds()

        const markAlpha = 0.7
        var ctx = getContext("2d")
        ctx.reset()
        ctx.translate(width / 2, height / 2)
        var radius = Math.min(width, height) / 2

        // Hour marks
        ctx.strokeStyle = Qt.alpha(clockColor, markAlpha)
        ctx.lineWidth = 2 * Style.uiScaleRatio
        var scaleFactor = 0.7

        for (var i = 0; i < 12; i++) {
          var scaleFactor = 0.8
          if (i % 3 === 0) {
            scaleFactor = 0.65
          }
          ctx.save()
          ctx.rotate(i * Math.PI / 6)
          ctx.beginPath()
          ctx.moveTo(0, -radius * scaleFactor)
          ctx.lineTo(0, -radius)
          ctx.stroke()
          ctx.restore()
        }

        // Hour hand
        ctx.save()
        var hourAngle = (hours % 12 + minutes / 60) * Math.PI / 6
        ctx.rotate(hourAngle)
        ctx.strokeStyle = clockColor
        ctx.lineWidth = 3 * Style.uiScaleRatio
        ctx.lineCap = "round"
        ctx.beginPath()
        ctx.moveTo(0, 0)
        ctx.lineTo(0, -radius * 0.6)
        ctx.stroke()
        ctx.restore()

        // Minute hand
        ctx.save()
        var minuteAngle = (minutes + seconds / 60) * Math.PI / 30
        ctx.rotate(minuteAngle)
        ctx.strokeStyle = clockColor
        ctx.lineWidth = 2 * Style.uiScaleRatio
        ctx.lineCap = "round"
        ctx.beginPath()
        ctx.moveTo(0, 0)
        ctx.lineTo(0, -radius * 0.9)
        ctx.stroke()
        ctx.restore()

        // Second hand
        ctx.save()
        var secondAngle = seconds * Math.PI / 30
        ctx.rotate(secondAngle)
        ctx.strokeStyle = secondHandColor
        ctx.lineWidth = 1.6 * Style.uiScaleRatio
        ctx.lineCap = "round"
        ctx.beginPath()
        ctx.moveTo(0, 0)
        ctx.lineTo(0, -radius)
        ctx.stroke()
        ctx.restore()

        // Center dot
        ctx.beginPath()
        ctx.arc(0, 0, 3 * Style.uiScaleRatio, 0, 2 * Math.PI)
        ctx.fillStyle = clockColor
        ctx.fill()
      }

      Component.onCompleted: requestPaint()
    }
  }

  // Digital Clock Component
  component NClockDigital: Item {
    property var now
    property color backgroundColor: Color.mPrimary
    property color clockColor: Color.mOnPrimary
    property color progressColor: Color.mError

    anchors.fill: parent

    // Digital clock's seconds circular progress
    Canvas {
      id: secondsProgress
      anchors.fill: parent
      property real progress: now.getSeconds() / 60
      onProgressChanged: requestPaint()
      Connections {
        target: Time
        function onNowChanged() {
          const total = now.getSeconds() * 1000 + now.getMilliseconds()
          secondsProgress.progress = total / 60000
        }
      }
      onPaint: {
        var ctx = getContext("2d")
        var centerX = width / 2
        var centerY = height / 2
        var radius = Math.min(width, height) / 2 - 3
        ctx.reset()

        // Background circle
        ctx.beginPath()
        ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI)
        ctx.lineWidth = 2.5
        ctx.strokeStyle = Qt.alpha(clockColor, 0.15)
        ctx.stroke()

        // Progress arc
        ctx.beginPath()
        ctx.arc(centerX, centerY, radius, -Math.PI / 2, -Math.PI / 2 + progress * 2 * Math.PI)
        ctx.lineWidth = 2.5
        ctx.strokeStyle = progressColor
        ctx.lineCap = "round"
        ctx.stroke()
      }
    }

    // Digital clock
    ColumnLayout {
      anchors.centerIn: parent
      spacing: -Style.marginXXS

      NText {
        text: {
          var t = Settings.data.location.use12hourFormat ? I18n.locale.toString(now, "hh AP") : I18n.locale.toString(now, "HH")
          return t.split(" ")[0]
        }

        pointSize: Style.fontSizeXS
        font.weight: Style.fontWeightBold
        color: clockColor
        family: Settings.data.ui.fontFixed
        Layout.alignment: Qt.AlignHCenter
      }

      NText {
        text: Qt.formatTime(now, "mm")
        pointSize: Style.fontSizeXXS
        font.weight: Style.fontWeightBold
        color: clockColor
        family: Settings.data.ui.fontFixed
        Layout.alignment: Qt.AlignHCenter
      }
    }
  }

  Component {
    id: analogClockComponent
    NClockAnalog {}
  }

  Component {
    id: digitalClockComponent
    NClockDigital {}
  }
}
