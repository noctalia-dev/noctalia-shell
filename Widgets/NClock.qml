import QtQuick
import QtQuick.Layouts
import Quickshell
import "../Helpers/ColorsConvert.js" as ColorsConvert
import qs.Commons
import qs.Widgets

Item {
  id: root

  property var now: Time.now

  // Style: "analog" or "digital"
  property string clockStyle: "analog"

  // Show seconds progress ring (digital only)
  property bool showProgress: true

  // Progress style: "solid" (continuous arc) or "dashed" (tick marks)
  property string progressStyle: "solid"

  // Color properties
  property color backgroundColor: Color.mPrimary
  property color clockColor: Color.mOnPrimary

  property color secondHandColor: {
    var defaultColor = Color.mError;
    var bestContrast = 1.0; // 1.0 is "no contrast"
    var bestColor = defaultColor;
    var candidates = [Color.mSecondary, Color.mTertiary, Color.mError];

    const minContrast = 1.149;

    for (var i = 0; i < candidates.length; i++) {
      var candidate = candidates[i];
      var contrastClock = ColorsConvert.getContrastRatio(candidate.toString(), clockColor.toString());
      if (contrastClock < minContrast) {
        continue;
      }
      var contrastBg = ColorsConvert.getContrastRatio(candidate.toString(), backgroundColor.toString());
      if (contrastBg < minContrast) {
        continue;
      }

      var currentWorstContrast = Math.min(contrastBg, contrastClock);

      if (currentWorstContrast > bestContrast) {
        bestContrast = currentWorstContrast;
        bestColor = candidate;
      }
    }

    return bestColor;
  }

  property color progressColor: root.secondHandColor

  // Font size properties for digital clock
  property real hoursFontSize: Style.fontSizeXS
  property real minutesFontSize: Style.fontSizeXXS
  property int hoursFontWeight: Style.fontWeightBold
  property int minutesFontWeight: Style.fontWeightBold

  // Scale ratio for canvas line widths (used by desktop widget scaling)
  property real scaleRatio: Style.uiScaleRatio

  height: Math.round((Style.fontSizeXXXL * 1.9) / 2 * Style.uiScaleRatio) * 2
  width: root.height

  Loader {
    id: clockLoader
    anchors.fill: parent

    sourceComponent: {
      if (root.clockStyle === "analog")
        return analogClockComponent;
      if (root.clockStyle === "binary")
        return binaryClockComponent;
      return digitalClockComponent;
    }

    onLoaded: {
      item.now = Qt.binding(function () {
        return root.now;
      });
      item.backgroundColor = Qt.binding(function () {
        return root.backgroundColor;
      });
      item.clockColor = Qt.binding(function () {
        return root.clockColor;
      });
      if (item.hasOwnProperty("secondHandColor")) {
        item.secondHandColor = Qt.binding(function () {
          return root.secondHandColor;
        });
      }
      if (item.hasOwnProperty("progressColor")) {
        item.progressColor = Qt.binding(function () {
          return root.progressColor;
        });
      }
      if (item.hasOwnProperty("hoursFontSize")) {
        item.hoursFontSize = Qt.binding(function () {
          return root.hoursFontSize;
        });
      }
      if (item.hasOwnProperty("minutesFontSize")) {
        item.minutesFontSize = Qt.binding(function () {
          return root.minutesFontSize;
        });
      }
      if ("hoursFontWeight" in item) {
        item.hoursFontWeight = Qt.binding(function () {
          return root.hoursFontWeight;
        });
      }
      if ("minutesFontWeight" in item) {
        item.minutesFontWeight = Qt.binding(function () {
          return root.minutesFontWeight;
        });
      }
      if (item.hasOwnProperty("scaleRatio")) {
        item.scaleRatio = Qt.binding(function () {
          return root.scaleRatio;
        });
      }
      if ("showProgress" in item) {
        item.showProgress = Qt.binding(function () {
          return root.showProgress;
        });
      }
      if ("progressStyle" in item) {
        item.progressStyle = Qt.binding(function () {
          return root.progressStyle;
        });
      }
    }
  }

  // Analog Clock Component
  component NClockAnalog: Item {
    property var now
    property color backgroundColor: Color.mPrimary
    property color clockColor: Color.mOnPrimary
    property color secondHandColor: Color.mError
    property real scaleRatio: Style.uiScaleRatio
    anchors.fill: parent

    Canvas {
      id: clockCanvas
      anchors.fill: parent

      Connections {
        target: Time
        function onNowChanged() {
          clockCanvas.requestPaint();
        }
      }

      onPaint: {
        var currentTime = Time.now;
        var hours = currentTime.getHours();
        var minutes = currentTime.getMinutes();
        var seconds = currentTime.getSeconds();

        const markAlpha = 0.7;
        var ctx = getContext("2d");
        ctx.reset();
        ctx.translate(width / 2, height / 2);
        var radius = Math.min(width, height) / 2;

        // Hour marks
        ctx.strokeStyle = Qt.alpha(clockColor, markAlpha);
        ctx.lineWidth = 2 * scaleRatio;
        var scaleFactor = 0.7;

        for (var i = 0; i < 12; i++) {
          var scaleFactor = 0.8;
          if (i % 3 === 0) {
            scaleFactor = 0.65;
          }
          ctx.save();
          ctx.rotate(i * Math.PI / 6);
          ctx.beginPath();
          ctx.moveTo(0, -radius * scaleFactor);
          ctx.lineTo(0, -radius);
          ctx.stroke();
          ctx.restore();
        }

        // Hour hand
        ctx.save();
        var hourAngle = (hours % 12 + minutes / 60) * Math.PI / 6;
        ctx.rotate(hourAngle);
        ctx.strokeStyle = clockColor;
        ctx.lineWidth = 3 * scaleRatio;
        ctx.lineCap = "round";
        ctx.beginPath();
        ctx.moveTo(0, 0);
        ctx.lineTo(0, -radius * 0.6);
        ctx.stroke();
        ctx.restore();

        // Minute hand
        ctx.save();
        var minuteAngle = (minutes + seconds / 60) * Math.PI / 30;
        ctx.rotate(minuteAngle);
        ctx.strokeStyle = clockColor;
        ctx.lineWidth = 2 * scaleRatio;
        ctx.lineCap = "round";
        ctx.beginPath();
        ctx.moveTo(0, 0);
        ctx.lineTo(0, -radius * 0.9);
        ctx.stroke();
        ctx.restore();

        // Second hand
        ctx.save();
        var secondAngle = seconds * Math.PI / 30;
        ctx.rotate(secondAngle);
        ctx.strokeStyle = secondHandColor;
        ctx.lineWidth = 1.6 * scaleRatio;
        ctx.lineCap = "round";
        ctx.beginPath();
        ctx.moveTo(0, 0);
        ctx.lineTo(0, -radius);
        ctx.stroke();
        ctx.restore();

        // Center dot
        ctx.beginPath();
        ctx.arc(0, 0, 3 * scaleRatio, 0, 2 * Math.PI);
        ctx.fillStyle = clockColor;
        ctx.fill();
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
    property real hoursFontSize: Style.fontSizeXS
    property real minutesFontSize: Style.fontSizeXXS
    property int hoursFontWeight: Style.fontWeightBold
    property int minutesFontWeight: Style.fontWeightBold
    property real scaleRatio: Style.uiScaleRatio
    property bool showProgress: true
    property string progressStyle: "solid"

    anchors.fill: parent

    // Digital clock's seconds circular progress
    Canvas {
      id: secondsProgress
      anchors.fill: parent
      visible: showProgress
      property real progress: now.getSeconds() / 60
      onProgressChanged: requestPaint()
      Connections {
        target: Time
        function onNowChanged() {
          const total = now.getSeconds() * 1000 + now.getMilliseconds();
          secondsProgress.progress = total / 60000;
        }
      }
      onPaint: {
        var ctx = getContext("2d");
        var centerX = width / 2;
        var centerY = height / 2;
        var radius = Math.min(width, height) / 2 - 3 * scaleRatio;
        ctx.reset();

        if (progressStyle === "dashed") {
          const numTicks = 60;
          const tickLength = 4.8 * scaleRatio;

          ctx.lineWidth = 2.5 * scaleRatio;
          ctx.lineCap = "round";

          ctx.save();
          ctx.translate(centerX, centerY);

          for (var i = 0; i < numTicks; i++) {
            ctx.save();
            ctx.rotate(-Math.PI / 2 + (i / numTicks) * 2 * Math.PI);

            var isActive = (i / numTicks) <= progress;
            ctx.strokeStyle = isActive ? progressColor : Qt.alpha(clockColor, 0.15);

            ctx.beginPath();
            ctx.moveTo(radius - tickLength / 2, 0);
            ctx.lineTo(radius + tickLength / 2, 0);
            ctx.stroke();
            ctx.restore();
          }
          ctx.restore();
        } else {
          // Background circle
          ctx.beginPath();
          ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI);
          ctx.lineWidth = 2.5 * scaleRatio;
          ctx.strokeStyle = Qt.alpha(clockColor, 0.15);
          ctx.stroke();

          // Progress arc
          ctx.beginPath();
          ctx.arc(centerX, centerY, radius, -Math.PI / 2, -Math.PI / 2 + progress * 2 * Math.PI);
          ctx.lineWidth = 2.5 * scaleRatio;
          ctx.strokeStyle = progressColor;
          ctx.lineCap = "round";
          ctx.stroke();
        }
      }
    }

    // Digital clock
    ColumnLayout {
      anchors.centerIn: parent
      spacing: -Style.marginXXS

      NText {
        text: {
          var t = Settings.data.location.use12hourFormat ? I18n.locale.toString(now, "hh AP") : I18n.locale.toString(now, "HH");
          return t.split(" ")[0];
        }

        pointSize: hoursFontSize
        font.weight: hoursFontWeight
        color: clockColor
        family: Settings.data.ui.fontFixed
        Layout.alignment: Qt.AlignHCenter
      }

      NText {
        text: Qt.formatTime(now, "mm")
        pointSize: minutesFontSize
        font.weight: minutesFontWeight
        color: clockColor
        family: Settings.data.ui.fontFixed
        Layout.alignment: Qt.AlignHCenter
      }
    }
  }

  // Binary Clock Component
  component NClockBinary: Item {
    property var now
    property color backgroundColor
    property color clockColor: Color.mOnPrimary

    anchors.fill: parent

    readonly property int h: now.getHours()
    readonly property int m: now.getMinutes()
    readonly property int s: now.getSeconds()

    // BCD (Binary Coded Decimal) Format:
    // H1 H2 : M1 M2 : S1 S2
    // H1 (tens): 0-2 (2 bits)
    // H2 (ones): 0-9 (4 bits)
    // M1 (tens): 0-5 (3 bits)
    // M2 (ones): 0-9 (4 bits)
    // S1 (tens): 0-5 (3 bits)
    // S2 (ones): 0-9 (4 bits)

    RowLayout {
      anchors.centerIn: parent
      spacing: parent.width * 0.05

      // Hours
      RowLayout {
        spacing: parent.parent.width * 0.02
        BinaryColumn {
          value: Math.floor(h / 10)
          bits: 2
          dotSize: root.width * 0.08
          activeColor: clockColor
          Layout.alignment: Qt.AlignBottom
        }
        BinaryColumn {
          value: h % 10
          bits: 4
          dotSize: root.width * 0.08
          activeColor: clockColor
          Layout.alignment: Qt.AlignBottom
        }
      }

      // Minutes
      RowLayout {
        spacing: parent.parent.width * 0.02
        BinaryColumn {
          value: Math.floor(m / 10)
          bits: 3
          dotSize: root.width * 0.08
          activeColor: clockColor
          Layout.alignment: Qt.AlignBottom
        }
        BinaryColumn {
          value: m % 10
          bits: 4
          dotSize: root.width * 0.08
          activeColor: clockColor
          Layout.alignment: Qt.AlignBottom
        }
      }

      // Seconds
      RowLayout {
        spacing: parent.parent.width * 0.02
        BinaryColumn {
          value: Math.floor(s / 10)
          bits: 3
          dotSize: root.width * 0.08
          activeColor: clockColor
          Layout.alignment: Qt.AlignBottom
        }
        BinaryColumn {
          value: s % 10
          bits: 4
          dotSize: root.width * 0.08
          activeColor: clockColor
          Layout.alignment: Qt.AlignBottom
        }
      }
    }
  }

  component BinaryColumn: Column {
    property int value: 0
    property int bits: 4
    property real dotSize: 10
    property color activeColor: "white"

    spacing: dotSize * 0.4

    Repeater {
      model: bits

      Rectangle {
        property int bitIndex: (bits - 1) - index
        property bool isActive: (value >> bitIndex) & 1

        width: dotSize
        height: dotSize
        radius: dotSize / 2
        color: isActive ? activeColor : Qt.alpha(activeColor, 0.2)

        Behavior on color {
          ColorAnimation {
            duration: 200
          }
        }
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

  Component {
    id: binaryClockComponent
    NClockBinary {}
  }
}
