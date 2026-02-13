import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

// Compact circular statistic display using Layout management
Item {
  id: root

  property real ratio: 0 // 0..1 range
  property string icon: ""
  property string suffix: "%"
  property real contentScale: 1.0
  property color fillColor: Color.mPrimary
  property string tooltipText: ""
  property string tooltipDirection: "top"

  // Arc geometry constants
  readonly property real _gaugeSize: 60 * contentScale
  readonly property real _lineWidth: 6 * contentScale
  readonly property real _arcRadius: _gaugeSize / 2 - 5 * contentScale
  // Arc goes from 150° to 390° (30°), gap at bottom
  // Bottom of arc is at y = center + radius * sin(30°) = center + radius * 0.5
  // Plus half line width for stroke
  readonly property real _arcBottomY: _gaugeSize / 2 + _arcRadius * 0.5 + _lineWidth / 2
  // Height needs to include the icon which sits inside the arc gap
  // Icon is ~12px tall, positioned 4px below text center, need ~4px more padding
  readonly property real _contentHeight: _arcBottomY + 4 * contentScale

  implicitWidth: Math.round(_gaugeSize)
  implicitHeight: Math.round(_contentHeight)
  Layout.maximumWidth: implicitWidth
  Layout.maximumHeight: implicitHeight

  // Animated ratio for smooth transitions - reduces repaint frequency
  property real animatedRatio: ratio

  Behavior on animatedRatio {
    enabled: !Settings.data.general.animationDisabled
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.OutCubic
    }
  }

  // Repaint gauge when animated ratio changes (throttled by animation)
  onAnimatedRatioChanged: {
    if (!repaintTimer.running) {
      repaintTimer.start();
    }
  }
  onFillColorChanged: gauge.requestPaint()

  // Throttle timer to limit repaint frequency during animation (~30 FPS)
  Timer {
    id: repaintTimer
    interval: 33
    repeat: true
    onTriggered: {
      gauge.requestPaint();
      // Stop repeating once animation settles
      if (Math.abs(root.animatedRatio - root.ratio) < 0.001) {
        stop();
      }
    }
  }

  Canvas {
    id: gauge
    width: root._gaugeSize
    height: root._gaugeSize
    anchors.horizontalCenter: parent.horizontalCenter
    y: 0

    // Optimized Canvas settings for better GPU performance
    renderStrategy: Canvas.Cooperative
    renderTarget: Canvas.FramebufferObject

    // Enable layer caching - critical for performance!
    layer.enabled: true
    layer.smooth: true

    // Hide until first paint to avoid white FBO flash
    visible: false
    onPainted: visible = true

    Component.onCompleted: {
      requestPaint();
    }

    onPaint: {
      const ctx = getContext("2d");
      const w = width, h = height;
      const cx = w / 2, cy = h / 2;
      const r = root._arcRadius;

      // Rotated 90° to the right: gap at the bottom
      // Start at 150° and end at 390° (30°) → bottom opening
      const start = Math.PI * 5 / 6; // 150°
      const endBg = Math.PI * 13 / 6; // 390° (equivalent to 30°)

      ctx.reset();
      ctx.lineWidth = root._lineWidth;
      ctx.lineCap = Settings.data.general.iRadiusRatio > 0 ? "round" : "butt";

      // Track uses outline for contrast against surfaceVariant backgrounds
      ctx.strokeStyle = Color.mSurface;
      ctx.beginPath();
      ctx.arc(cx, cy, r, start, endBg);
      ctx.stroke();

      // Value arc - only draw if ratio is meaningful (> 0.5%)
      const r2 = Math.max(0, Math.min(1, root.animatedRatio));
      if (r2 > 0.005) {
        const end = start + (endBg - start) * r2;
        ctx.strokeStyle = root.fillColor;
        ctx.beginPath();
        ctx.arc(cx, cy, r, start, end);
        ctx.stroke();
      }
    }
  }

  // Percent centered in the circle
  NText {
    id: valueLabel
    anchors.horizontalCenter: gauge.horizontalCenter
    anchors.verticalCenter: gauge.verticalCenter
    anchors.verticalCenterOffset: -4 * root.contentScale
    text: `${Math.round(root.animatedRatio * 100)}${root.suffix}`
    pointSize: Style.fontSizeM * root.contentScale * 0.9
    font.weight: Style.fontWeightBold
    color: root.fillColor
    horizontalAlignment: Text.AlignHCenter
  }

  NIcon {
    id: iconText
    anchors.horizontalCenter: gauge.horizontalCenter
    anchors.top: valueLabel.bottom
    anchors.topMargin: 4 * root.contentScale
    icon: root.icon
    color: root.fillColor
    pointSize: Style.fontSizeM * root.contentScale
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onEntered: {
      if (root.tooltipText) {
        TooltipService.show(root, root.tooltipText, root.tooltipDirection);
      }
    }
    onExited: {
      if (root.tooltipText) {
        TooltipService.hide();
      }
    }
  }
}
