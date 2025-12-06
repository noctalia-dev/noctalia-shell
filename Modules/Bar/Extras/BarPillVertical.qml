import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  required property ShellScreen screen

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
  property bool rotateText: false
  property color customBackgroundColor: Color.transparent
  property color customTextIconColor: Color.transparent

  readonly property bool collapseToIcon: forceClose && !forceOpen

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

  // Sizing logic for vertical bars
  readonly property int buttonSize: Style.capsuleHeight
  readonly property int pillHeight: buttonSize
  readonly property int pillOverlap: Math.round(buttonSize * 0.5)
  readonly property int maxPillWidth: rotateText ? Math.max(buttonSize, Math.round(textItem.implicitHeight + Style.marginM * 2)) : buttonSize
  readonly property int maxPillHeight: rotateText ? Math.max(1, Math.round(textItem.implicitWidth + Style.marginM * 2 + Math.round(iconCircle.height / 4))) : Math.max(1, Math.round(textItem.implicitHeight + Style.marginM * 2))

  // Determine pill direction based on section position
  readonly property bool openDownward: oppositeDirection
  readonly property bool openUpward: !oppositeDirection

  // Effective shown state (true if animated open or forced, but not if force closed)
  readonly property bool revealed: !forceClose && (forceOpen || showPill)
  readonly property bool hasIcon: root.icon !== ""

  // Always prioritize hover color, then the custom one and finally the fallback color
  readonly property color bgColor: hovered ? Color.mHover : (customBackgroundColor.a > 0) ? customBackgroundColor : Style.capsuleColor
  readonly property color fgColor: hovered ? Color.mOnHover : (customTextIconColor.a > 0) ? customTextIconColor : Color.mOnSurface

  readonly property real iconSize: {
    switch (root.density) {
    case "compact":
      return Math.max(1, Math.round(pillHeight * 0.65));
    default:
      return Math.max(1, Math.round(pillHeight * 0.48));
    }
  }

  readonly property real textSize: {
    switch (root.density) {
    case "compact":
      return Math.max(1, Math.round(pillHeight * 0.38));
    default:
      return Math.max(1, Math.round(pillHeight * 0.33));
    }
  }

  // For vertical bars: width is just icon size, height includes pill space
  width: buttonSize
  height: {
    if (collapseToIcon) {
      return hasIcon ? buttonSize : 0;
    }
    if (revealed) {
      var overlap = hasIcon ? pillOverlap : 0;
      var baseHeight = hasIcon ? buttonSize : 0;
      return baseHeight + Math.max(0, maxPillHeight - overlap);
    }
    // Fallback to buttonSize in idle state to remain clickable
    return buttonSize;
  }

  Connections {
    target: root
    function onTooltipTextChanged() {
      if (hovered) {
        TooltipService.updateText(root.tooltipText);
      }
    }
  }

  // Unified background for the entire pill area to avoid overlapping opacity
  Rectangle {
    id: pillBackground
    width: buttonSize
    height: root.height
    radius: Style.radiusM
    color: root.bgColor
    anchors.verticalCenter: parent.verticalCenter
    anchors.horizontalCenter: parent.horizontalCenter

    Behavior on color {
      ColorAnimation {
        duration: Style.animationFast
        easing.type: Easing.InOutQuad
      }
    }
  }

  Rectangle {
    id: pill

    width: revealed ? maxPillWidth : 1
    height: revealed ? maxPillHeight : 1

    // Position based on direction - center the pill relative to the icon
    x: 0
    y: {
      if (!hasIcon)
        return 0;
      return openUpward ? (iconCircle.y + iconCircle.height / 2 - height) : (iconCircle.y + iconCircle.height / 2);
    }

    opacity: revealed ? Style.opacityFull : Style.opacityNone
    color: Color.transparent // Make pill background transparent to avoid double opacity

    // Radius logic for vertical expansion - rounded on the side that connects to icon
    topLeftRadius: openUpward ? Style.radiusM : 0
    bottomLeftRadius: openDownward ? Style.radiusM : 0
    topRightRadius: openUpward ? Style.radiusM : 0
    bottomRightRadius: openDownward ? Style.radiusM : 0

    anchors.horizontalCenter: parent.horizontalCenter

    NText {
      id: textItem
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: hasIcon ? (openDownward ? Style.marginXXS : -Style.marginXXS) : 0
      rotation: rotateText ? -90 : 0
      text: root.text + root.suffix
      family: Settings.data.ui.fontFixed
      pointSize: textSize
      applyUiScale: false
      font.weight: Style.fontWeightMedium
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      color: root.fgColor
      visible: revealed

      function getVerticalCenterOffset() {
        // A small, symmetrical offset to push the text slightly away from the icon's edge.
        return openDownward ? Style.marginXS : -Style.marginXS;
      }
    }
    Behavior on width {
      enabled: showAnim.running || hideAnim.running
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.OutCubic
      }
    }
    Behavior on height {
      enabled: showAnim.running || hideAnim.running
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.OutCubic
      }
    }
    Behavior on opacity {
      enabled: showAnim.running || hideAnim.running
      NumberAnimation {
        duration: Style.animationFast
        easing.type: Easing.OutCubic
      }
    }
  }

  Rectangle {
    id: iconCircle
    width: buttonSize
    height: buttonSize
    radius: Math.min(Style.radiusL, width / 2)
    color: Color.transparent // Make icon background transparent to avoid double opacity

    // Icon positioning based on direction
    x: 0
    y: openUpward ? (parent.height - height) : 0
    anchors.horizontalCenter: parent.horizontalCenter

    NIcon {
      icon: root.icon
      pointSize: iconSize
      applyUiScale: false
      color: root.fgColor
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
      property: "height"
      from: 1
      to: maxPillHeight
      duration: Style.animationNormal
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: pill
      property: "opacity"
      from: 0
      to: 1
      duration: Style.animationFast
      easing.type: Easing.OutCubic
    }
    onStarted: {
      showPill = true;
    }
    onStopped: {
      delayedHideAnim.start();
      root.shown();
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
                hideAnim.start();
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
      property: "height"
      from: maxPillHeight
      to: 1
      duration: Style.animationNormal
      easing.type: Easing.InCubic
    }
    NumberAnimation {
      target: pill
      property: "opacity"
      from: 1
      to: 0
      duration: Style.animationFast
      easing.type: Easing.InCubic
    }
    onStopped: {
      showPill = false;
      shouldAnimateHide = false;
      root.hidden();
    }
  }

  Timer {
    id: showTimer
    interval: Style.pillDelay
    onTriggered: {
      if (!showPill) {
        showAnim.start();
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onEntered: {
      hovered = true;
      root.entered();
      TooltipService.show(pill, root.tooltipText, BarService.getTooltipDirection(), (forceOpen || forceClose) ? Style.tooltipDelay : Style.tooltipDelayLong);
      if (forceClose) {
        return;
      }
      if (!forceOpen) {
        showDelayed();
      }
    }
    onExited: {
      hovered = false;
      root.exited();
      if (!forceOpen && !forceClose) {
        hide();
      }
      TooltipService.hide();
    }
    onClicked: function (mouse) {
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

  function show() {
    if (collapseToIcon || root.text.trim().length === 0)
      return;
    if (!showPill) {
      shouldAnimateHide = autoHide;
      showAnim.start();
    } else {
      hideAnim.stop();
      delayedHideAnim.restart();
    }
  }

  function hide() {
    if (collapseToIcon)
      return;
    if (forceOpen) {
      return;
    }
    if (showPill) {
      hideAnim.start();
    }
    showTimer.stop();
  }

  function showDelayed() {
    if (collapseToIcon || root.text.trim().length === 0)
      return;
    if (!showPill) {
      shouldAnimateHide = autoHide;
      showTimer.start();
    } else {
      hideAnim.stop();
      delayedHideAnim.restart();
    }
  }

  onForceOpenChanged: {
    if (forceOpen) {
      // Immediately lock open without animations
      showAnim.stop();
      hideAnim.stop();
      delayedHideAnim.stop();
      showPill = true;
    } else {
      hide();
    }
  }
}
