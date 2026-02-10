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
  property var tooltipText: ""
  property bool autoHide: false
  property bool forceOpen: false
  property bool forceClose: false
  property bool oppositeDirection: false
  property bool hovered: false
  property color customBackgroundColor: "transparent"
  property color customTextIconColor: "transparent"
  property color customIconColor: "transparent"
  property color customTextColor: "transparent"

  readonly property bool collapseToIcon: forceClose && !forceOpen

  // Effective shown state (true if hovered/animated open or forced)
  readonly property bool revealed: !forceClose && (forceOpen || showPill)
  readonly property bool hasIcon: root.icon !== ""

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

  readonly property int pillHeight: Style.getCapsuleHeightForScreen(screen?.name)
  readonly property real barFontSize: Style.getBarFontSizeForScreen(screen?.name)
  readonly property int pillPaddingHorizontal: Math.round(pillHeight * 0.2)
  readonly property int pillOverlap: Math.round(pillHeight * 0.5)
  readonly property int pillMaxWidth: Math.max(1, Math.round(textItem.implicitWidth + pillPaddingHorizontal * 2 + pillOverlap))

  // Always prioritize hover color, then the custom one and finally the fallback color
  readonly property color bgColor: hovered ? Color.mHover : (customBackgroundColor.a > 0) ? customBackgroundColor : Style.capsuleColor
  readonly property color fgColor: hovered ? Color.mOnHover : (customTextIconColor.a > 0) ? customTextIconColor : Color.mOnSurface
  readonly property color iconFgColor: hovered ? Color.mOnHover : (customIconColor.a > 0) ? customIconColor : (customTextIconColor.a > 0) ? customTextIconColor : Color.mOnSurface
  readonly property color textFgColor: hovered ? Color.mOnHover : (customTextColor.a > 0) ? customTextColor : (customTextIconColor.a > 0) ? customTextIconColor : Color.mOnSurface

  readonly property real iconSize: Style.toOdd(pillHeight * 0.48)

  // Content width calculation (for implicit sizing)
  readonly property real contentWidth: {
    if (collapseToIcon) {
      return hasIcon ? pillHeight : 0;
    }
    var overlap = hasIcon ? pillOverlap : 0;
    var baseWidth = hasIcon ? pillHeight : 0;
    return baseWidth + Math.max(0, pill.width - overlap);
  }

  // Fill parent to extend click area to full bar height
  // Visual content is centered vertically within
  anchors.fill: parent
  implicitWidth: contentWidth
  implicitHeight: pillHeight

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
    width: collapseToIcon ? pillHeight : root.width
    height: pillHeight
    radius: Style.radiusM
    color: root.bgColor
    anchors.verticalCenter: parent.verticalCenter
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    Behavior on color {
      enabled: !Color.isTransitioning
      ColorAnimation {
        duration: Style.animationFast
        easing.type: Style.easingTypeSlow
        easing.bezierCurve: Style.easingCurveSlow
      }
    }
  }

  Rectangle {
    id: pill

    width: revealed ? pillMaxWidth : 1
    height: pillHeight

    x: {
      if (!hasIcon)
        return 0;
      return oppositeDirection ? (iconCircle.x + iconCircle.width / 2) : (iconCircle.x + iconCircle.width / 2) - width;
    }

    opacity: revealed ? Style.opacityFull : Style.opacityNone
    color: "transparent" // Make pill background transparent to avoid double opacity

    topLeftRadius: oppositeDirection ? 0 : Style.radiusM
    bottomLeftRadius: oppositeDirection ? 0 : Style.radiusM
    topRightRadius: oppositeDirection ? Style.radiusM : 0
    bottomRightRadius: oppositeDirection ? Style.radiusM : 0
    anchors.verticalCenter: parent.verticalCenter

    NText {
      id: textItem
      anchors.verticalCenter: parent.verticalCenter
      x: {
        if (!hasIcon)
          return (parent.width - width) / 2;

        // Better text horizontal centering
        var centerX = (parent.width - width) / 2;
        var offset = oppositeDirection ? Style.marginXS : -Style.marginXS;
        if (forceOpen) {
          // If its force open, the icon disc background is the same color as the bg pill move text slightly
          offset += oppositeDirection ? -Style.marginXXS : Style.marginXXS;
        }
        return centerX + offset;
      }
      text: root.text + root.suffix
      family: Settings.data.ui.fontFixed
      pointSize: root.barFontSize
      applyUiScale: false
      color: root.textFgColor
      visible: revealed
    }

    Behavior on width {
      enabled: showAnim.running || hideAnim.running
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Style.easingTypeDefault
        easing.bezierCurve: Style.easingCurveDefault
      }
    }
    Behavior on opacity {
      enabled: showAnim.running || hideAnim.running
      NumberAnimation {
        duration: Style.animationFast
        easing.type: Style.easingTypeDefault
        easing.bezierCurve: Style.easingCurveDefault
      }
    }
  }

  Rectangle {
    id: iconCircle
    width: hasIcon ? pillHeight : 0
    height: pillHeight
    radius: Math.min(Style.radiusL, width / 2)
    color: "transparent" // Make icon background transparent to avoid double opacity
    anchors.verticalCenter: parent.verticalCenter

    x: oppositeDirection ? 0 : (parent.width - width)

    NIcon {
      icon: root.icon
      pointSize: iconSize
      applyUiScale: false
      color: root.iconFgColor
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
      easing.type: Style.easingTypeDefault
      easing.bezierCurve: Style.easingCurveDefault
    }
    NumberAnimation {
      target: pill
      property: "opacity"
      from: 0
      to: 1
      duration: Style.animationFast
      easing.type: Style.easingTypeDefault
      easing.bezierCurve: Style.easingCurveDefault
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
    cursorShape: root.clicked ? Qt.PointingHandCursor : Qt.ArrowCursor
    onEntered: {
      hovered = true;
      root.entered();
      TooltipService.show(root, root.tooltipText, BarService.getTooltipDirection(root.screen?.name), (forceOpen || forceClose) ? Style.tooltipDelay : Style.tooltipDelayLong);
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
