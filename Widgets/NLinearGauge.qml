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
    property real fillHeight: root.height * Math.min(1, Math.max(0, root.ratio))
    property real fillWidth: root.width * Math.min(1, Math.max(0, root.ratio))
    width: orientation === Qt.Vertical ? root.width : fillWidth
    height: orientation === Qt.Vertical ? fillHeight : root.height
    radius: root.radius
    color: root.fillColor
    anchors.bottom: parent.bottom
    anchors.left: parent.left
  }
}
