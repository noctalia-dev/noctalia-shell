import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Compact circular statistic display using Layout management
Rectangle {
  id: root

  property real value: 0 // 0..100 (or any range visually mapped)
  property string icon: ""
  property string suffix: "%"
  // When nested inside a parent group (NBox), you can make it flat
  property bool flat: false
  // Scales the internal content (labels, gauge, icon) without changing the
  // outer width/height footprint of the component
  property real contentScale: 1.0

  property color fillColor: Color.mPrimary
  property color textColor: Color.mOnSurface

  width: 68
  height: 92
  color: flat ? Color.transparent : Color.mSurface
  radius: Style.iRadiusS
  border.color: flat ? Color.transparent : Color.mSurfaceVariant
  border.width: flat ? 0 : Style.borderS

  // Animated value for smooth transitions - reduces repaint frequency
  property real animatedValue: value

  Behavior on animatedValue {
    enabled: !Settings.data.general.animationDisabled
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.OutCubic
    }
  }

  // Repaint gauge when animated value changes (throttled by animation)
  onAnimatedValueChanged: repaintTimer.restart()
  onFillColorChanged: repaintTimer.restart()

  // Debounce timer to limit repaint frequency during rapid value changes
  Timer {
    id: repaintTimer
    interval: 33 // ~30 FPS max
    repeat: false
    onTriggered: gauge.requestPaint()
  }

  ColumnLayout {
    id: mainLayout
    anchors.fill: parent
    anchors.margins: Style.marginS * contentScale
    spacing: 0

    // Main gauge container
    Item {
      id: gaugeContainer
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.alignment: Qt.AlignCenter
      Layout.preferredWidth: 68 * contentScale
      Layout.preferredHeight: 68 * contentScale

      Canvas {
        id: gauge
        anchors.fill: parent

        // Optimized Canvas settings for better GPU performance
        renderStrategy: Canvas.Cooperative // Better performance than Immediate
        renderTarget: Canvas.FramebufferObject // GPU texture rendering

        // Enable layer caching - critical for performance!
        layer.enabled: true
        layer.smooth: true

        Component.onCompleted: {
          requestPaint();
        }

        onPaint: {
          const ctx = getContext("2d");
          const w = width, h = height;
          const cx = w / 2, cy = h / 2;
          const r = Math.min(w, h) / 2 - 5 * contentScale;

          // Rotated 90° to the right: gap at the bottom
          // Start at 150° and end at 390° (30°) → bottom opening
          const start = Math.PI * 5 / 6; // 150°
          const endBg = Math.PI * 13 / 6; // 390° (equivalent to 30°)

          ctx.reset();
          ctx.lineWidth = 6 * contentScale;

          // Track uses surface for stronger contrast
          ctx.strokeStyle = Color.mSurface;
          ctx.beginPath();
          ctx.arc(cx, cy, r, start, endBg);
          ctx.stroke();

          // Value arc with gradient starting at 25%
          const ratio = Math.max(0, Math.min(1, root.animatedValue / 100));
          const end = start + (endBg - start) * ratio;

          ctx.strokeStyle = root.fillColor;
          ctx.beginPath();
          ctx.arc(cx, cy, r, start, end);
          ctx.stroke();
        }
      }

      // Percent centered in the circle
      NText {
        id: valueLabel
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -4 * contentScale
        text: `${Math.round(root.value)}${root.suffix}`
        pointSize: Style.fontSizeM * contentScale * 0.9
        font.weight: Style.fontWeightBold
        color: root.fillColor
        horizontalAlignment: Text.AlignHCenter
      }

      NIcon {
        id: iconText
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: valueLabel.bottom
        anchors.topMargin: 8 * contentScale
        icon: root.icon
        color: root.fillColor
        pointSize: Style.fontSizeM
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
  }
}
