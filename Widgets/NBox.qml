import QtQuick
import qs.Commons

// Rounded group container using the variant surface color.
// To be used in side panels and settings panes to group fields or buttons.
Rectangle {
  id: root

  color: Color.mSurfaceVariant
  radius: Style.radiusM
  border.color: Color.mOutline
  border.width: Style.borderS
}
