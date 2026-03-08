import QtQuick
import qs.Commons
import qs.Services.UI

Rectangle {
  id: root

  // Mandatory properties for gauges
  required property int orientation // Qt.Vertical || Qt.Horizontal
  required property real ratio // 0..1

  radius: orientation === Qt.Vertical ? width / 2 : height / 2
  color: Color.mOutline
  property color fillColor: Color.mPrimary

  // Fill that grows from bottom if vertical and left if horizontal.
  // Snap to zero if the computed pixel length is sub-pixel (< 1px).
  Rectangle {
    readonly property real clampedRatio: Math.min(1, Math.max(0, root.ratio))
    readonly property real rawFill: (orientation === Qt.Vertical ? root.height : root.width) * clampedRatio
    width: orientation === Qt.Vertical ? root.width : (rawFill < 1 ? 0 : rawFill)
    height: orientation === Qt.Vertical ? (rawFill < 1 ? 0 : rawFill) : root.height
    radius: root.radius
    color: root.fillColor
    anchors.bottom: orientation === Qt.Vertical ? parent.bottom : undefined
    anchors.left: parent.left
  }
}
