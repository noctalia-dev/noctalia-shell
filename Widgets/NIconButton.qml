import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Services

Rectangle {
  id: root

  // Multiplier to control how large the button container is relative to Style.baseWidgetSize
  property real sizeMultiplier: 1.0
  property real size: Style.baseWidgetSize * sizeMultiplier * scaling
  property string icon
  property string tooltipText
  property bool showBorder: true
  property bool showFilled: false
  property bool enabled: true
  property bool hovering: false
  property real fontPointSize: Style.fontSizeMedium

  signal entered
  signal exited
  signal clicked

  implicitWidth: size
  implicitHeight: size

  color: (root.hovering || showFilled) ? Color.mPrimary : Color.transparent
  radius: width * 0.5
  border.color: showBorder ? Color.mPrimary : Color.transparent
  border.width: Math.max(1, Style.borderThin * scaling)

  NIcon {
    anchors.centerIn: parent
    // Little hack to keep things centered at high scaling
    anchors.horizontalCenterOffset: -1 * (scaling - 1.0)
    anchors.verticalCenterOffset: 0
    text: root.icon
    font.pointSize: root.fontPointSize * scaling
    color: (root.hovering || showFilled) ? Color.mOnPrimary : showBorder ? Color.mPrimary : Color.mOnSurface
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    opacity: root.enabled ? Style.opacityFull : Style.opacityMedium
  }

  NTooltip {
    id: tooltip
    target: root
    positionAbove: false
    text: root.tooltipText
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    onEntered: {
      hovering = true
      if (tooltipText) {
        tooltip.show()
      }
      root.entered()
    }
    onExited: {
      hovering = false
      if (tooltipText) {
        tooltip.hide()
      }
      root.exited()
    }
    onClicked: {
      if (tooltipText) {
        tooltip.hide()
      }
      root.clicked()
    }
  }
}
