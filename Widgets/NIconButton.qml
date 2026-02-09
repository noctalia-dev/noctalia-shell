import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Services.UI

Item {
  id: root

  property real baseSize: Style.baseWidgetSize
  property bool applyUiScale: true

  property string icon
  property string tooltipText
  property string tooltipDirection: "auto"
  property bool allowClickWhenDisabled: false
  property bool hovering: false

  property color colorBg: Color.mSurfaceVariant
  property color colorFg: Color.mPrimary
  property color colorBgHover: Color.mHover
  property color colorFgHover: Color.mOnHover
  property color colorBorder: Color.mOutline
  property color colorBorderHover: Color.mOutline
  property real customRadius: -1 // -1 means use default (iRadiusL), otherwise use this value

  // Expose border properties for backwards compatibility (aliases to visualButton)
  property alias border: visualButton.border
  property alias radius: visualButton.radius
  property alias color: visualButton.color

  signal entered
  signal exited
  signal clicked
  signal rightClicked
  signal middleClicked
  signal wheel(int angleDelta)

  // Calculate button size based on settings
  readonly property real buttonSize: applyUiScale ? Style.toOdd(baseSize * Style.uiScaleRatio) : Style.toOdd(baseSize)

  // Size: use implicit width/height which layout can override
  // BarWidgetLoader sets explicit width/height to extend click area
  implicitWidth: buttonSize
  implicitHeight: buttonSize

  opacity: root.enabled ? Style.opacityFull : Style.opacityMedium

  // Visual button - stays at buttonSize, centered in parent
  Rectangle {
    id: visualButton
    width: root.buttonSize
    height: root.buttonSize
    anchors.centerIn: parent

    color: root.enabled && root.hovering ? colorBgHover : colorBg
    radius: Math.min((customRadius >= 0 ? customRadius : Style.iRadiusL), width / 2)
    border.color: root.enabled && root.hovering ? colorBorderHover : colorBorder
    border.width: Style.borderS

    Behavior on color {
      enabled: !Color.isTransitioning
      ColorAnimation {
        duration: Style.animationFast
        easing.type: Style.easingTypeFast
      }
    }

    NIcon {
      icon: root.icon
      pointSize: Style.toOdd(visualButton.width * 0.48)
      applyUiScale: root.applyUiScale
      color: root.enabled && root.hovering ? colorFgHover : colorFg
      // Pixel-perfect centering
      x: Style.pixelAlignCenter(visualButton.width, width)
      y: Style.pixelAlignCenter(visualButton.height, contentHeight)

      Behavior on color {
        enabled: !Color.isTransitioning
        ColorAnimation {
          duration: Style.animationFast
          easing.type: Style.easingTypeFast
        }
      }
    }
  }

  // MouseArea fills root (extends beyond visual button for bar click area)
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
        TooltipService.show(root, tooltipText, tooltipDirection);
      }
      root.entered();
    }
    onExited: {
      hovering = false;
      if (tooltipText) {
        TooltipService.hide(root);
      }
      root.exited();
    }
    onClicked: function (mouse) {
      if (tooltipText) {
        TooltipService.hide(root);
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
