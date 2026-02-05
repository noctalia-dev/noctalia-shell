import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Battery widget with Android 16 style rendering (horizontal or vertical)
Item {
  id: root

  // Data (must be provided by parent)
  required property real percentage
  required property bool charging
  required property bool pluggedIn
  required property bool ready
  required property bool low

  // Sizing - baseSize controls overall scaleFactor for bar/panel usage
  property real baseSize: Style.fontSizeM

  // Styling - no hardcoded colors, only theme colors
  property color baseColor: Color.mOnSurface
  property color lowColor: Color.mError
  property color chargingColor: Color.mPrimary
  property color textColor: Color.mSurface

  // Display options
  property bool showPercentageText: true
  property bool vertical: false

  // Alternating state icon display (toggles between percentage and icon when charging/plugged)
  property bool showStateIcon: false

  onHasStateIconChanged: {
    if (!hasStateIcon)
      showStateIcon = false;
  }

  // Internal sizing calculations based on baseSize
  readonly property real scaleFactor: baseSize / Style.fontSizeM
  readonly property real bodyWidth: Style.toOdd(22 * scaleFactor)
  readonly property real bodyHeight: Style.toOdd(14 * scaleFactor)
  readonly property real terminalWidth: Math.round(2.5 * scaleFactor)
  readonly property real terminalHeight: Math.round(7 * scaleFactor)
  readonly property real cornerRadius: Math.round(3 * scaleFactor)

  // Total size is just body + terminal (no external icon)
  readonly property real totalWidth: vertical ? bodyHeight : bodyWidth + terminalWidth
  readonly property real totalHeight: vertical ? bodyWidth + terminalWidth : bodyHeight

  // Determine active color based on state
  readonly property color activeColor: {
    if (!ready) {
      return Qt.alpha(baseColor, Style.opacityMedium);
    }
    if (charging) {
      return chargingColor;
    }
    if (low) {
      return lowColor;
    }
    return baseColor;
  }

  // Background color for empty portion (semi-transparent)
  readonly property color emptyColor: Qt.alpha(baseColor, 0.7)

  // State icon logic
  readonly property bool hasStateIcon: (!ready || charging || pluggedIn)
  readonly property string stateIcon: {
    if (!ready)
      return "x";
    if (charging)
      return "bolt-filled";
    if (pluggedIn)
      return "plug-filled";
    return "";
  }

  // Animated percentage for smooth transitions
  property real animatedPercentage: percentage

  Behavior on animatedPercentage {
    enabled: !Settings.data.general.animationDisabled
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.OutCubic
    }
  }

  // Timer to alternate between percentage text and state icon when charging/plugged
  Timer {
    id: alternateTimer
    interval: 3000
    repeat: true
    running: root.hasStateIcon && root.ready
    onTriggered: root.showStateIcon = !root.showStateIcon
  }

  implicitWidth: Math.round(totalWidth)
  implicitHeight: Math.round(totalHeight)
  Layout.maximumWidth: implicitWidth
  Layout.maximumHeight: implicitHeight

  // Battery body container
  Item {
    id: batteryBody
    width: root.vertical ? root.bodyHeight : root.bodyWidth + root.terminalWidth
    height: root.vertical ? root.bodyWidth + root.terminalWidth : root.bodyHeight
    anchors.left: root.vertical ? undefined : parent.left
    anchors.bottom: root.vertical ? parent.bottom : undefined
    anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
    anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter

    // Battery body background
    Rectangle {
      id: bodyBackground
      y: root.vertical ? root.terminalWidth : 0
      width: root.vertical ? root.bodyHeight : root.bodyWidth
      height: root.vertical ? root.bodyWidth : root.bodyHeight
      radius: root.cornerRadius
      color: root.emptyColor
    }

    // Terminal cap
    Rectangle {
      x: root.vertical ? (root.bodyHeight - root.terminalHeight) / 2 : root.bodyWidth
      y: root.vertical ? 0 : (root.bodyHeight - root.terminalHeight) / 2
      width: root.vertical ? root.terminalHeight : root.terminalWidth
      height: root.vertical ? root.terminalWidth : root.terminalHeight
      radius: root.cornerRadius / 2
      color: root.emptyColor
    }

    // Fill level
    Rectangle {
      id: fillRect
      visible: root.ready && root.animatedPercentage > 0
      x: 0
      y: root.vertical ? root.terminalWidth + root.bodyWidth * (1 - root.animatedPercentage / 100) : 0
      width: root.vertical ? root.bodyHeight : root.bodyWidth * (root.animatedPercentage / 100)
      height: root.vertical ? root.bodyWidth * (root.animatedPercentage / 100) : root.bodyHeight
      radius: root.cornerRadius
      color: root.activeColor
    }
  }

  // Percentage text overlaid on battery center
  NText {
    id: percentageText
    visible: opacity > 0
    opacity: root.showPercentageText && root.ready && !root.showStateIcon ? 1 : 0
    x: batteryBody.x + Style.pixelAlignCenter(bodyBackground.width, width)
    y: batteryBody.y + bodyBackground.y + Style.pixelAlignCenter(bodyBackground.height, height)
    font.family: Settings.data.ui.fontFixed
    font.weight: Style.fontWeightBold
    text: root.vertical ? String(Math.round(root.animatedPercentage)).split('').join('\n') : Math.round(root.animatedPercentage)
    pointSize: root.baseSize * (root.vertical ? 0.82 : 0.82)
    color: Qt.alpha(root.textColor, 0.75)
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    lineHeight: root.vertical ? 0.7 : 1.0
    lineHeightMode: Text.ProportionalHeight

    Behavior on opacity {
      enabled: !Settings.data.general.animationDisabled
      NumberAnimation {
        duration: Style.animationFast
        easing.type: Easing.InOutQuad
      }
    }
  }

  // State icon centered inside battery body (shown when alternating)
  NIcon {
    id: stateIconOverlay
    visible: opacity > 0
    opacity: !root.ready || (root.hasStateIcon && root.showStateIcon) ? 1 : 0
    x: batteryBody.x + Style.pixelAlignCenter(bodyBackground.width, width)
    y: batteryBody.y + bodyBackground.y + Style.pixelAlignCenter(bodyBackground.height, height)
    icon: root.stateIcon
    pointSize: Style.toOdd(root.baseSize)
    color: Qt.alpha(root.textColor, 0.75)

    Behavior on opacity {
      enabled: !Settings.data.general.animationDisabled
      NumberAnimation {
        duration: Style.animationFast
        easing.type: Easing.InOutQuad
      }
    }
  }
}
