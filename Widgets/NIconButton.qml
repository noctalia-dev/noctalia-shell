import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Services.UI

Rectangle {
  id: root

  property real baseSize: Style.baseWidgetSize
  property bool applyUiScale: true

  property string icon
  property string tooltipText
  property string tooltipDirection: "auto"
  property string density: ""
  property bool enabled: true
  property bool allowClickWhenDisabled: false
  property bool hovering: false

  property color colorBg: Color.mSurfaceVariant
  property color colorFg: Color.mPrimary
  property color colorBgHover: Color.mHover
  property color colorFgHover: Color.mOnHover
  property color colorBorder: Color.mOutline
  property color colorBorderHover: Color.mOutline
  property real customRadius: -1 // -1 means use default (iRadiusL), otherwise use this value

  signal entered
  signal exited
  signal clicked
  signal rightClicked
  signal middleClicked
  signal wheel(int angleDelta)

  implicitWidth: applyUiScale ? Math.round(baseSize * Style.uiScaleRatio) : Math.round(baseSize)
  implicitHeight: applyUiScale ? Math.round(baseSize * Style.uiScaleRatio) : Math.round(baseSize)

  opacity: root.enabled ? Style.opacityFull : Style.opacityMedium
  color: root.enabled && root.hovering ? colorBgHover : colorBg
  radius: Math.min((customRadius >= 0 ? customRadius : Style.iRadiusL), width / 2)
  border.color: root.enabled && root.hovering ? colorBorderHover : colorBorder
  border.width: Style.borderS

  Behavior on color {
    ColorAnimation {
      duration: Style.animationNormal
      easing.type: Easing.InOutQuad
    }
  }

  NIcon {
    icon: root.icon
    pointSize: {
      switch (root.density) {
      case "compact":
        return Math.max(1, root.width * 0.65);
      default:
        return Math.max(1, root.width * 0.48);
      }
    }
    applyUiScale: root.applyUiScale
    color: root.enabled && root.hovering ? colorFgHover : colorFg
    // Pixel-perfect centering
    x: Style.pixelAlignCenter(root.width, width)
    y: Style.pixelAlignCenter(root.height, contentHeight)

    Behavior on color {
      ColorAnimation {
        duration: Style.animationFast
        easing.type: Easing.InOutQuad
      }
    }
  }

  MouseArea {
    // Always enabled to allow hover/tooltip even when the button is disabled
    enabled: true
    anchors.fill: parent
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    hoverEnabled: true
    onEntered: {
      hovering = root.enabled ? true : false;
      if (tooltipText) {
        TooltipService.show(parent, tooltipText, tooltipDirection);
      }
      root.entered();
    }
    onExited: {
      hovering = false;
      if (tooltipText) {
        TooltipService.hide();
      }
      root.exited();
    }
    onClicked: function (mouse) {
      if (tooltipText) {
        TooltipService.hide();
      }
      if (!root.enabled && !allowClickWhenDisabled) {
        return;
      }
      if (mouse.button === Qt.LeftButton) {
        root.clicked();
      } else if (mouse.button === Qt.RightButton) {
        root.rightClicked();
      } else if (mouse.button === Qt.MiddleButton) {
        root.middleClicked();
      }
    }
    onWheel: wheel => root.wheel(wheel.angleDelta.y)
  }
}
