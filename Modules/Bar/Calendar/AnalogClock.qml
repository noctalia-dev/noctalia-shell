import QtQuick
import qs.Commons
import Quickshell

Item {
  property var now
  property color backgroundColor: Color.mPrimary
  property color clockColor: Color.mOnPrimary
  property color secondHandColor: Color.mError
  anchors.fill: parent

  Canvas {
    id: clockCanvas
    anchors.fill: parent

    property int hours: now.getHours()
    property int minutes: now.getMinutes()
    property int seconds: now.getSeconds()

    onPaint: {
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

    Timer {
      interval: 1000
      running: true
      repeat: true
      onTriggered: {
        clockCanvas.hours = now.getHours()
        clockCanvas.minutes = now.getMinutes()
        clockCanvas.seconds = now.getSeconds()
        clockCanvas.requestPaint()
      }
    }

    Component.onCompleted: requestPaint()
  }
}
