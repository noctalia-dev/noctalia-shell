import QtQuick
import qs.Commons

Item {
  id: root

  property bool running: true
  property color color: Color.mPrimary
  property int size: Style.baseWidgetSize
  property int strokeWidth: Style.borderL
  property int duration: Style.animationSlow * 2

  implicitWidth: size
  implicitHeight: size

  // GPU-optimized spinner - draw once, rotate with GPU transform
  Item {
    id: spinner
    anchors.fill: parent

    // Static canvas - drawn ONCE, then cached
    Canvas {
      id: canvas
      anchors.fill: parent
      renderStrategy: Canvas.Cooperative // Better performance than Threaded for simple shapes
      renderTarget: Canvas.FramebufferObject // GPU texture

      // Enable layer caching - critical for performance!
      layer.enabled: true
      layer.smooth: true

      Component.onCompleted: {
        requestPaint()
      }

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()

        var centerX = width / 2
        var centerY = height / 2
        var radius = Math.min(width, height) / 2 - strokeWidth / 2

        ctx.strokeStyle = root.color
        ctx.lineWidth = Math.max(1, root.strokeWidth)
        ctx.lineCap = "round"

        // Draw arc with gap (270 degrees = 3/4 of circle)
        ctx.beginPath()
        ctx.arc(centerX, centerY, radius, -Math.PI / 2, -Math.PI / 2 + Math.PI * 1.5)
        ctx.stroke()
      }
    }

    // Smooth rotation animation - uses GPU transform, NO canvas repaints!
    RotationAnimation on rotation {
      running: root.running
      from: 0
      to: 360
      duration: root.duration
      loops: Animation.Infinite
    }
  }
}
