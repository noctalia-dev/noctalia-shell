import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Widgets

Item {
  id: root

  required property ShellScreen screen

  property string icon: ""
  property string text: ""
  property string suffix: ""
  property string tooltipText: ""
  property bool autoHide: false
  property bool forceOpen: false
  property bool forceClose: false
  property bool oppositeDirection: false
  property bool hovered: false
  property bool rotateText: false
  property color customBackgroundColor: "transparent"
  property color customTextIconColor: "transparent"

  readonly property string barPosition: Settings.data.bar.position
  readonly property bool isVerticalBar: barPosition === "left" || barPosition === "right"

  signal shown
  signal hidden
  signal entered
  signal exited
  signal clicked
  signal rightClicked
  signal middleClicked
  signal wheel(int delta)

  // Dynamic sizing based on loaded component
  width: pillLoader.item ? pillLoader.item.width : 0
  height: pillLoader.item ? pillLoader.item.height : 0

  // Loader to switch between vertical and horizontal pill implementations
  Loader {
    id: pillLoader
    sourceComponent: isVerticalBar ? verticalPillComponent : horizontalPillComponent

    Component {
      id: verticalPillComponent
      BarPillVertical {
        screen: root.screen
        icon: root.icon
        text: root.text
        suffix: root.suffix
        tooltipText: root.tooltipText
        autoHide: root.autoHide
        forceOpen: root.forceOpen
        forceClose: root.forceClose
        oppositeDirection: root.oppositeDirection
        hovered: root.hovered
        rotateText: root.rotateText
        customBackgroundColor: root.customBackgroundColor
        customTextIconColor: root.customTextIconColor
        onShown: root.shown()
        onHidden: root.hidden()
        onEntered: root.entered()
        onExited: root.exited()
        onClicked: root.clicked()
        onRightClicked: root.rightClicked()
        onMiddleClicked: root.middleClicked()
        onWheel: delta => root.wheel(delta)
      }
    }

    Component {
      id: horizontalPillComponent
      BarPillHorizontal {
        screen: root.screen
        icon: root.icon
        text: root.text
        suffix: root.suffix
        tooltipText: root.tooltipText
        autoHide: root.autoHide
        forceOpen: root.forceOpen
        forceClose: root.forceClose
        oppositeDirection: root.oppositeDirection
        hovered: root.hovered
        customBackgroundColor: root.customBackgroundColor
        customTextIconColor: root.customTextIconColor
        onShown: root.shown()
        onHidden: root.hidden()
        onEntered: root.entered()
        onExited: root.exited()
        onClicked: root.clicked()
        onRightClicked: root.rightClicked()
        onMiddleClicked: root.middleClicked()
        onWheel: delta => root.wheel(delta)
      }
    }
  }

  function show() {
    if (pillLoader.item && pillLoader.item.show) {
      pillLoader.item.show();
    }
  }

  function hide() {
    if (pillLoader.item && pillLoader.item.hide) {
      pillLoader.item.hide();
    }
  }

  function showDelayed() {
    if (pillLoader.item && pillLoader.item.showDelayed) {
      pillLoader.item.showDelayed();
    }
  }
}
