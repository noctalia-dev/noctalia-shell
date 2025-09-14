import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Services

Item {
  id: root

  property string icon: ""
  property string text: ""
  property string suffix: ""
  property string tooltipText: ""
  property real sizeRatio: 0.8
  property bool autoHide: false
  property bool forceOpen: false
  property bool forceClose: false
  property bool disableOpen: false
  property bool rightOpen: false
  property bool hovered: false

  // Effective shown state (true if hovered/animated open or forced)
  readonly property bool revealed: forceOpen || showPill

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

  // Exposed width logic
  readonly property int iconSize: Math.round(Style.baseWidgetSize * sizeRatio * scaling)
  readonly property int pillHeight: iconSize
  readonly property int pillPaddingHorizontal: Style.marginXS * scaling
  readonly property int pillOverlap: iconSize * 0.5
  readonly property int maxPillWidth: Math.max(1, textItem.implicitWidth + pillPaddingHorizontal * 2 + pillOverlap)

  width: iconSize + Math.max(0, pill.width - pillOverlap)
  height: pillHeight

  Rectangle {
    id: pill
    width: revealed ? maxPillWidth : 1
    height: pillHeight

    x: rightOpen ? (iconCircle.x + iconCircle.width / 2) : // Opens right
                   (iconCircle.x + iconCircle.width / 2) - width // Opens left

    opacity: revealed ? Style.opacityFull : Style.opacityNone
    color: Color.mSurfaceVariant

    topLeftRadius: rightOpen ? 0 : pillHeight * 0.5
    bottomLeftRadius: rightOpen ? 0 : pillHeight * 0.5
    topRightRadius: rightOpen ? pillHeight * 0.5 : 0
    bottomRightRadius: rightOpen ? pillHeight * 0.5 : 0
    anchors.verticalCenter: parent.verticalCenter

    NText {
      id: textItem
      anchors.verticalCenter: parent.verticalCenter
      x: {
        // Better text horizontal centering
        var centerX = (parent.width - width) / 2
        var offset = rightOpen ? Style.marginXS * scaling : -Style.marginXS * scaling
        if (forceOpen) {
          // If its force open, the icon disc background is the same color as the bg pill move text slightly
          offset += rightOpen ? -Style.marginXXS * scaling : Style.marginXXS * scaling
        }
        return centerX + offset
      }
      text: root.text + root.suffix
      font.family: Settings.data.ui.fontFixed
      font.pointSize: Style.fontSizeXS * scaling
      font.weight: Style.fontWeightBold
      color: Color.mOnSurface
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
    width: iconSize
    height: iconSize
    radius: width * 0.5
    color: hovered && !forceOpen ? Color.mTertiary : Color.mSurfaceVariant
    anchors.verticalCenter: parent.verticalCenter

    x: rightOpen ? 0 : (parent.width - width)

    Behavior on color {
      ColorAnimation {
        duration: Style.animationNormal
        easing.type: Easing.InOutQuad
      }
    }

    NIcon {
      icon: root.icon
      font.pointSize: Style.fontSizeM * scaling
      color: hovered && !forceOpen ? Color.mOnTertiary : Color.mOnSurface
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
      to: maxPillWidth
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
      from: maxPillWidth
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

  NTooltip {
    id: tooltip
    positionAbove: Settings.data.bar.position === "bottom"
    target: pill
    delay: Style.tooltipDelayLong
    text: root.tooltipText
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
      tooltip.show()
      if (disableOpen) {
        return
      }
      if (!forceOpen) {
        showDelayed()
      }
    }
    onExited: {
      hovered = false
      root.exited()
      if (!forceOpen) {
        hide()
      }
      tooltip.hide()
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
    onWheel: wheel => {
               root.wheel(wheel.angleDelta.y)
             }
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
