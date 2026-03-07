import QtQuick
import qs.Commons

// Rounded group container using the variant surface color.
// To be used in side panels and settings panes to group fields or buttons.
Item {
  id: root

  property color color: Color.mSurfaceVariant
  property bool forceOpaque: false
  property alias radius: bg.radius
  property alias border: bg.border

  Rectangle {
    id: bg
    anchors.fill: parent
    color: forceOpaque ? root.color : Qt.alpha(root.color, root.color.a * Settings.data.ui.panelBackgroundOpacity)
    radius: Style.radiusM
    border.color: Style.boxBorderColor
    border.width: Style.borderS
  }
}
