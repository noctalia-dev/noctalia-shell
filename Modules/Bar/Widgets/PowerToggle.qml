import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

NIconButton {
  id: root

  property ShellScreen screen
  property real scaling: 1.0

  icon: "power"
  tooltipText: "Power Settings"
  sizeRatio: 0.8
  colorBg: Color.mSurfaceVariant
  colorFg: Color.mError
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent
  anchors.verticalCenter: parent.verticalCenter
  onClicked: PanelService.getPanel("powerPanel")?.toggle()
}
