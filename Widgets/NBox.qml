import QtQuick
import qs.Commons

// Rounded group container using the variant surface color.
// To be used in side panels and settings panes to group fields or buttons.
// Use a reduced opacity (1/3 of panel's opactity) to ensure readability
Item {
  id: root

  property color color: Color.mSurfaceVariant
  property bool forceOpaque: false
  property alias radius: bg.radius
  property alias border: bg.border

  Rectangle {
    id: bg
    anchors.fill: parent
    color: forceOpaque ? root.color : Qt.alpha(root.color, Math.max(0, root.color.a - (1.0 - Settings.data.ui.panelBackgroundOpacity) * 0.33))
    radius: Style.radiusM
    border.color: Style.boxBorderColor
    border.width: Style.borderS
  }
}
