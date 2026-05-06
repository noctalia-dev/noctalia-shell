import QtQuick
import qs.Commons
import qs.Services.Compositor

Item {
  id: root

  visible: CompositorService.isDriftwm && CompositorService.canvasZoom > 0

  readonly property real currentZoom: CompositorService.canvasZoom
  readonly property string zoomText: "\u00D7" + (currentZoom >= 1 ? currentZoom.toFixed(1) : currentZoom.toFixed(2))

  implicitWidth: zoomLabel.implicitWidth + Style.marginS * 2
  implicitHeight: Style.barHeight

  Text {
    id: zoomLabel
    anchors.centerIn: parent
    text: root.zoomText
    font.pixelSize: Style.fontSizeS
    font.weight: Font.Medium
    color: Qt.rgba(1, 1, 1, 0.7)
  }
}
