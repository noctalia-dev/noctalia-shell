import QtQuick
import qs.Commons

// Rounded group container using the variant surface color.
// To be used in side panels and settings panes to group fields or buttons.
// Opacity is based on panelBackgroundOpacity but clamped to a minimum to avoid full transparency.

Item {
  id: root

  property color color: Color.mSurfaceVariant
  property bool forceOpaque: false
  property alias radius: bg.radius
  property alias border: bg.border

  Rectangle {
    id: bg
    anchors.fill: parent
    radius: Style.radiusM
    border.color: Style.boxBorderColor
    border.width: Style.borderS
    color: {
      if (forceOpaque) {
        return root.color;
      }

      // Reuse panel opacity, but limit it to 0.5
      let alpha = Math.max(Settings.data.ui.panelBackgroundOpacity, 0.4);
      alpha = Math.max(0, root.color.a - (1.0 - alpha));
      return Qt.alpha(root.color, alpha);
    }
  }
}
