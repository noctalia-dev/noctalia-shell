import QtQuick
import QtQuick.Layouts

import qs.Commons
import qs.Widgets

Item {
  Layout.preferredWidth: 70
  Layout.preferredHeight: 70
  Layout.alignment: Qt.AlignVCenter

  // Seconds circular progress
  Canvas {
    id: secondsProgress
    anchors.fill: parent

    property real progress: Time.date.getSeconds() / 60
    onProgressChanged: requestPaint()

    Connections {
      target: Time
      function onDateChanged() {
        const total = Time.date.getSeconds() * 1000 + Time.date.getMilliseconds()
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
      ctx.strokeStyle = Qt.alpha(Color.mOnSurface, 0.15)
      ctx.stroke()

      // Progress arc
      ctx.beginPath()
      ctx.arc(centerX, centerY, radius, -Math.PI / 2, -Math.PI / 2 + progress * 2 * Math.PI)
      ctx.lineWidth = 2.5
      ctx.strokeStyle = Color.mPrimary
      ctx.lineCap = "round"
      ctx.stroke()
    }
  }

  // Digital clock
  ColumnLayout {
    anchors.centerIn: parent
    spacing: 0

    NText {
      text: {
        var t = Settings.data.location.use12hourFormat ? Qt.locale().toString(Time.date, "hh AP") : Qt.locale().toString(Time.date, "HH")
        return t
      }
      pointSize: Style.fontSizeM
      font.weight: Style.fontWeightBold
      family: Settings.data.ui.fontFixed
      color: Color.mOnSurface
      horizontalAlignment: Text.AlignHCenter
      Layout.alignment: Qt.AlignHCenter
    }

    NText {
      text: Qt.formatTime(Time.date, "mm")
      pointSize: Style.fontSizeM
      font.weight: Style.fontWeightBold
      family: Settings.data.ui.fontFixed
      color: Color.mOnSurfaceVariant
      horizontalAlignment: Text.AlignHCenter
      Layout.alignment: Qt.AlignHCenter
    }
  }
}
