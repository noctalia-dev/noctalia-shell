import QtQuick
import qs.Commons
import qs.Services.UI

Rectangle {
  id: root

  // Mandatory properties for gauges
  required property int orientation // Qt.Vertical || Qt.Horizontal
  required property real ratio // 0..1

  radius: width / 2
  color: Color.mOutline
  property color fillColor: Color.mPrimary

  // Fill that grows from bottom if vertical and left if horizontal
  Rectangle {
    readonly property real clampedRatio: Math.min(1, Math.max(0, root.ratio))
    // Enforce a minimum fill size equal to the gauge thickness so the fill
    // always renders as a rounded pill rather than a flat line at low values
    width: orientation === Qt.Vertical ? root.width : (clampedRatio > 0 ? Math.max(root.height, root.width * clampedRatio) : 0)
    height: orientation === Qt.Vertical ? (clampedRatio > 0 ? Math.max(root.width, root.height * clampedRatio) : 0) : root.height
    radius: root.radius
    color: root.fillColor
    anchors.bottom: orientation === Qt.Vertical ? parent.bottom : undefined
    anchors.left: parent.left
  }
}
