import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI

Rectangle {
  id: root

  property bool show: false
  property string tooltipText: ""

  implicitWidth: root.show ? 6 * Style.uiScaleRatio : 0
  implicitHeight: root.show ? 6 * Style.uiScaleRatio : 0
  width: root.show ? 6 * Style.uiScaleRatio : 0
  height: root.show ? 6 * Style.uiScaleRatio : 0
  radius: width / 2
  color: Color.mOnSurfaceVariant
  opacity: 0.6

  visible: root.show

  Behavior on opacity {
    NumberAnimation {
      duration: Style.animationFast
    }
  }

  MouseArea {
    enabled: root.show && root.tooltipText !== ""
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    cursorShape: Qt.PointingHandCursor

    onEntered: {
      if (root.tooltipText) {
        TooltipService.show(root, root.tooltipText);
      }
    }

    onExited: {
      if (root.tooltipText) {
        TooltipService.hide();
      }
    }
  }
}
