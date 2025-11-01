import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

Item {
  id: root

  property ShellScreen screen

  property string icon: ""
  property string text: ""
  property string suffix: ""
  property string tooltipText: ""
  property string density: ""
  property bool autoHide: false
  property bool forceOpen: false
  property bool forceClose: false
  property bool oppositeDirection: false
  property bool hovered: false

  // Effective shown state (true if hovered/animated open or forced)
  readonly property bool revealed: !forceClose && (forceOpen || showPill)

  signal shown
  signal hidden
  signal entered
  signal exited
  signal clicked
  signal rightClicked
  signal middleClicked
  signal wheel(int delta)

  // Internal state
  property bool showPill: false
  property bool shouldAnimateHide: false

  readonly property int pillHeight: Style.capsuleHeight
  readonly property int pillPaddingHorizontal: Math.round(Style.capsuleHeight * 0.2)
  readonly property int pillOverlap: Math.round(Style.capsuleHeight * 0.5)
  readonly property int pillMaxWidth: Math.max(1, Math.round(textItem.implicitWidth + pillPaddingHorizontal * 2 + pillOverlap))

  readonly property real iconSize: {
    switch (root.density) {
    case "compact":
      return Math.max(1, Math.round(pillHeight * 0.65))
    default:
      return Math.max(1, Math.round(pillHeight * 0.48))
    }
  }

  readonly property real textSize: {
    switch (root.density) {
    case "compact":
      return Math.max(1, Math.round(pillHeight * 0.45))
    default:
      return Math.max(1, Math.round(pillHeight * 0.33))
    }
  }

  width: pillHeight + Math.max(0, pill.width - pillOverlap)
  height: pillHeight

  Connections {
    target: root
    function onTooltipTextChanged() {
      if (hovered) {
        TooltipService.updateText(root.tooltipText)
      }
    }
  }

  Rectangle {
    id: pill

    width: revealed ? pillMaxWidth : 1
    height: pillHeight

    x: oppositeDirection ? (iconCircle.x + iconCircle.width / 2) : // Opens right
                           (iconCircle.x + iconCircle.width / 2) - width // Opens left

    opacity: revealed ? Style.opacityFull : Style.opacityNone
    color: Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent

    readonly property int halfPillHeight: Math.round(pillHeight * 0.5)

    topLeftRadius: oppositeDirection ? 0 : halfPillHeight
    bottomLeftRadius: oppositeDirection ? 0 : halfPillHeight
    topRightRadius: oppositeDirection ? halfPillHeight : 0
    bottomRightRadius: oppositeDirection ? halfPillHeight : 0
    anchors.verticalCenter: parent.verticalCenter

    NText {
      id: textItem
      anchors.verticalCenter: parent.verticalCenter
      x: {
        // Better text horizontal centering
        var centerX = (parent.width - width) / 2
        var offset = oppositeDirection ? Style.marginXS : -Style.marginXS
        if (forceOpen) {
          // If its force open, the icon disc background is the same color as the bg pill move text slightly
          offset += oppositeDirection ? -Style.marginXXS : Style.marginXXS
        }
        return centerX + offset
      }
      text: root.text + root.suffix
      family: Settings.data.ui.fontFixed
      pointSize: textSize
      applyUiScale: false
      font.weight: Style.fontWeightBold
      color: forceOpen ? Color.mOnSurface : Color.mPrimary
      visible: revealed
    }

    Behavior on width {
      enabled: showAnim.running || hideAnim.running
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.OutCubic
      }
    }
    Behavior on opacity {
      enabled: showAnim.running || hideAnim.running
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.OutCubic
      }
    }
  }

  Rectangle {
    id: iconCircle
    width: pillHeight
    height: pillHeight
    radius: width * 0.5
    color: hovered ? Color.mHover : Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent
    anchors.verticalCenter: parent.verticalCenter

    x: oppositeDirection ? 0 : (parent.width - width)

    Behavior on color {
      ColorAnimation {
        duration: Style.animationNormal
        easing.type: Easing.InOutQuad
      }
    }

    NIcon {
      icon: root.icon
      pointSize: iconSize
      applyUiScale: false
      color: hovered ? Color.mOnHover : Color.mOnSurface
      // Center horizontally
      x: (iconCircle.width - width) / 2
      // Center vertically accounting for font metrics
      y: (iconCircle.height - height) / 2 + (height - contentHeight) / 2
    }
  }

  ParallelAnimation {
    id: showAnim
    running: false
    NumberAnimation {
      target: pill
      property: "width"
      from: 1
      to: pillMaxWidth
      duration: Style.animationNormal
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: pill
      property: "opacity"
      from: 0
      to: 1
      duration: Style.animationNormal
      easing.type: Easing.OutCubic
    }
    onStarted: {
      showPill = true
    }
    onStopped: {
      delayedHideAnim.start()
      root.shown()
    }
  }

  SequentialAnimation {
    id: delayedHideAnim
    running: false
    PauseAnimation {
      duration: 2500
    }
    ScriptAction {
      script: if (shouldAnimateHide) {
                hideAnim.start()
              }
    }
  }

  ParallelAnimation {
    id: hideAnim
    running: false
    NumberAnimation {
      target: pill
      property: "width"
      from: pillMaxWidth
      to: 1
      duration: Style.animationNormal
      easing.type: Easing.InCubic
    }
    NumberAnimation {
      target: pill
      property: "opacity"
      from: 1
      to: 0
      duration: Style.animationNormal
      easing.type: Easing.InCubic
    }
    onStopped: {
      showPill = false
      shouldAnimateHide = false
      root.hidden()
    }
  }

  Timer {
    id: showTimer
    interval: Style.pillDelay
    onTriggered: {
      if (!showPill) {
        showAnim.start()
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onEntered: {
      hovered = true
      root.entered()
      TooltipService.show(Screen, pill, root.tooltipText, BarService.getTooltipDirection(), Style.tooltipDelayLong)
      if (forceClose) {
        return
      }
      if (!forceOpen) {
        showDelayed()
      }
    }
    onExited: {
      hovered = false
      root.exited()
      if (!forceOpen && !forceClose) {
        hide()
      }
      TooltipService.hide()
    }
    onClicked: function (mouse) {
      if (mouse.button === Qt.LeftButton) {
        root.clicked()
      } else if (mouse.button === Qt.RightButton) {
        root.rightClicked()
      } else if (mouse.button === Qt.MiddleButton) {
        root.middleClicked()
      }
    }
    onWheel: wheel => root.wheel(wheel.angleDelta.y)
  }

  function show() {
    if (!showPill) {
      shouldAnimateHide = autoHide
      showAnim.start()
    } else {
      hideAnim.stop()
      delayedHideAnim.restart()
    }
  }

  function hide() {
    if (forceOpen) {
      return
    }
    if (showPill) {
      hideAnim.start()
    }
    showTimer.stop()
  }

  function showDelayed() {
    if (!showPill) {
      shouldAnimateHide = autoHide
      showTimer.start()
    } else {
      hideAnim.stop()
      delayedHideAnim.restart()
    }
  }

  onForceOpenChanged: {
    if (forceOpen) {
      // Immediately lock open without animations
      showAnim.stop()
      hideAnim.stop()
      delayedHideAnim.stop()
      showPill = true
    } else {
      hide()
    }
  }
}
