import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Services

Item {
  id: root

  property string icon: ""
  property string text: ""
  property string tooltipText: ""
  property color pillColor: Color.mSurfaceVariant
  property color textColor: Color.mOnSurface
  property color iconCircleColor: Color.mPrimary
  property color iconTextColor: Color.mSurface
  property color collapsedIconColor: Color.mOnSurface
  property real sizeMultiplier: 0.8
  property bool autoHide: false
  property bool forceOpen: false
  property bool disableOpen: false

  // Effective shown state (true if hovered/animated open or forced)
  readonly property bool effectiveShown: forceOpen || showPill

  signal shown
  signal hidden
  signal entered
  signal exited
  signal clicked
  signal wheel(int delta)

  // Internal state
  property bool showPill: false
  property bool shouldAnimateHide: false

  property string iconSide: "right"
  readonly property int seamOverlap: Math.ceil(1 * scaling)
  // Exposed width logic
  readonly property int pillHeight: Style.baseWidgetSize * sizeMultiplier * scaling
  readonly property int iconSize: Style.baseWidgetSize * sizeMultiplier * scaling
  readonly property int pillPaddingHorizontal: Style.marginM * scaling
  readonly property int pillOverlap: iconSize * 0.5
  readonly property int maxPillWidth: Math.max(1, textItem.implicitWidth + pillPaddingHorizontal * 2 + pillOverlap)

  width: iconSize + (effectiveShown ? maxPillWidth - pillOverlap : 0)
  height: pillHeight

  Rectangle {
    id: pill
    width: effectiveShown ? maxPillWidth : 1
    height: pillHeight
  x: iconSide === "right"
     ? (iconCircle.x + iconCircle.width / 2) - width - seamOverlap
     : (iconCircle.x + iconCircle.width / 2) + seamOverlap
    opacity: effectiveShown ? Style.opacityFull : Style.opacityNone
    color: pillColor
  topLeftRadius: iconSide === "right" ? pillHeight * 0.5 : 0
  bottomLeftRadius: iconSide === "right" ? pillHeight * 0.5 : 0
  topRightRadius: iconSide === "left" ? pillHeight * 0.5 : 0
  bottomRightRadius: iconSide === "left" ? pillHeight * 0.5 : 0
    anchors.verticalCenter: parent.verticalCenter

    NText {
      id: textItem
      anchors.centerIn: parent
      text: root.text
      font.pointSize: Style.fontSizeXS * scaling
      font.weight: Style.fontWeightBold
      color: textColor
      visible: effectiveShown
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
    // Smooth color transition to match iconCircle and avoid right-edge seam when hovering
    Behavior on color {
      ColorAnimation {
        duration: Style.animationNormal
        easing.type: Easing.InOutQuad
      }
    }
  }

  Rectangle {
    id: iconCircle
    width: iconSize
    height: iconSize
    radius: width * 0.5
    // When forced shown, match pill background; otherwise use accent when hovered
    color: forceOpen ? pillColor : (showPill ? iconCircleColor : Color.mSurfaceVariant)
    anchors.verticalCenter: parent.verticalCenter
    anchors.right: parent.right

    Behavior on color {
      ColorAnimation {
        duration: Style.animationNormal
        easing.type: Easing.InOutQuad
      }
    }

    NIcon {
      text: root.icon
      font.pointSize: Style.fontSizeM * scaling
      // When forced shown, use pill text color; otherwise accent color when hovered
      color: forceOpen ? textColor : (showPill ? iconTextColor : Color.mOnSurface)
      anchors.centerIn: parent
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
    onEntered: {
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
      root.exited()
      if (!forceOpen) {
        hide()
      }
      tooltip.hide()
    }
    onClicked: {
      root.clicked()
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
