import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.System
import qs.Widgets

Item {
  id: root

  property string title: ""
  property string description: ""
  property string icon: ""
  property string type: "notice"
  property int duration: 3000
  property string actionLabel: ""
  property var actionCallback: null
  readonly property real initialScale: 0.7

  signal hidden

  readonly property int notificationWidth: Math.round(440 * Style.uiScaleRatio)
  readonly property int shadowPadding: Style.shadowBlurMax + Style.marginL

  width: notificationWidth + shadowPadding * 2
  height: Math.round(contentLayout.implicitHeight + Style.margin2M * 2 + shadowPadding * 2)
  visible: true
  opacity: 0
  scale: initialScale

  property real progress: 1.0
  property int hoverCount: 0
  property real swipeOffset: 0
  property real swipeOffsetY: 0
  property real pressGlobalX: 0
  property real pressGlobalY: 0
  property bool isSwiping: false
  readonly property string location: Settings.data.notifications?.location || "top_right"
  readonly property bool isLeft: location.endsWith("_left")
  readonly property bool isRight: location.endsWith("_right")
  readonly property bool useVerticalSwipe: location === "bottom" || location === "top"
  readonly property real swipeStartThreshold: Math.round(18 * Style.uiScaleRatio)
  readonly property real swipeDismissThreshold: Math.max(110, background.width * 0.32)
  readonly property real verticalSwipeDismissThreshold: Math.max(70, background.height * 0.35)

  transform: Translate {
    x: root.swipeOffset
    y: root.swipeOffsetY
  }

  function clampSwipeDelta(deltaX) {
    if (isRight)
      return Math.max(0, deltaX);
    if (isLeft)
      return Math.min(0, deltaX);
    return deltaX;
  }

  function clampVerticalSwipeDelta(deltaY) {
    if (location === "bottom")
      return Math.max(0, deltaY);
    if (location === "top")
      return Math.min(0, deltaY);
    return deltaY;
  }

  onHoverCountChanged: {
    if (hoverCount > 0) {
      resumeTimer.stop();
      if (progressAnimation.running && !progressAnimation.paused) {
        progressAnimation.pause();
      }
    } else {
      resumeTimer.start();
    }
  }

  Timer {
    id: resumeTimer
    interval: 50
    repeat: false
    onTriggered: {
      if (hoverCount === 0 && progressAnimation.paused) {
        progressAnimation.resume();
      }
    }
  }

  // Background rectangle (apply shadows here)
  Rectangle {
    id: background
    anchors.fill: parent
    anchors.margins: shadowPadding
    radius: Style.radiusL
    color: Qt.alpha(Color.mSurface, Settings.data.notifications.backgroundOpacity || 1.0)

    // Colored border based on type
    border.width: Style.borderS
    border.color: {
      var baseColor;
      switch (root.type) {
      case "error":
        baseColor = Color.mError;
        break;
      default:
        baseColor = Color.mOutline;
        break;
      }
      return Qt.alpha(baseColor, Settings.data.notifications.backgroundOpacity || 1.0);
    }

    // Progress bar
    Rectangle {
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: 2
      color: "transparent"

      Rectangle {
        id: progressBar
        readonly property real progressWidth: background.width - (2 * background.radius)
        height: parent.height
        // Mirrored logic: centers the bar as it shrinks
        x: background.radius + (progressWidth * (1 - root.progress)) / 2
        width: progressWidth * root.progress

        color: {
          var baseColor;
          switch (root.type) {
          case "warning":
            baseColor = Color.mPrimary;
            break;
          case "error":
            baseColor = Color.mError;
            break;
          default:
            baseColor = Color.mPrimary; // Match standard notification color
            break;
          }
          return Qt.alpha(baseColor, Settings.data.notifications.backgroundOpacity || 1.0);
        }
      }
    }
  }

  NDropShadow {
    anchors.fill: background
    source: background
    autoPaddingEnabled: true
  }

  NumberAnimation {
    id: progressAnimation
    target: root
    property: "progress"
    from: 1.0
    to: 0.0
    duration: root.duration
    easing.type: Easing.Linear
    onFinished: {
      if (root.progress === 0.0 && root.visible) {
        root.hide();
      }
    }
  }

  // Timer: hideTimer removed, using progressAnimation

  Behavior on opacity {
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.OutCubic
    }
  }

  Behavior on scale {
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.OutCubic
    }
  }

  Behavior on swipeOffset {
    enabled: !root.isSwiping
    NumberAnimation {
      duration: Style.animationFast
      easing.type: Easing.OutCubic
    }
  }

  Behavior on swipeOffsetY {
    enabled: !root.isSwiping
    NumberAnimation {
      duration: Style.animationFast
      easing.type: Easing.OutCubic
    }
  }

  Timer {
    id: hideAnimation
    interval: Style.animationFast
    onTriggered: {
      root.visible = false;
      root.hidden();
    }
  }

  // Cleanup on destruction
  Component.onDestruction: {
    progressAnimation.stop();
    hideAnimation.stop();
  }

  // Click anywhere dismiss the toast (must be before content so action link can override)
  MouseArea {
    id: toastDragArea
    anchors.fill: background
    acceptedButtons: Qt.LeftButton
    hoverEnabled: true
    onEntered: {
      root.hoverCount++;
    }
    onExited: {
      root.hoverCount--;
    }
    onPressed: mouse => {
                 const globalPoint = toastDragArea.mapToGlobal(mouse.x, mouse.y);
                 root.pressGlobalX = globalPoint.x;
                 root.pressGlobalY = globalPoint.y;
                 root.isSwiping = false;
               }
    onPositionChanged: mouse => {
                         if (!(mouse.buttons & Qt.LeftButton))
                         return;
                         const globalPoint = toastDragArea.mapToGlobal(mouse.x, mouse.y);
                         const rawDeltaX = globalPoint.x - root.pressGlobalX;
                         const rawDeltaY = globalPoint.y - root.pressGlobalY;
                         const deltaX = root.clampSwipeDelta(rawDeltaX);
                         const deltaY = root.clampVerticalSwipeDelta(rawDeltaY);
                         if (!root.isSwiping) {
                           if (root.useVerticalSwipe) {
                             if (Math.abs(deltaY) < root.swipeStartThreshold)
                             return;
                             root.isSwiping = true;
                           } else {
                             if (Math.abs(deltaX) < root.swipeStartThreshold)
                             return;
                             root.isSwiping = true;
                           }
                         }
                         if (root.useVerticalSwipe) {
                           root.swipeOffset = 0;
                           root.swipeOffsetY = deltaY;
                         } else {
                           root.swipeOffset = deltaX;
                           root.swipeOffsetY = 0;
                         }
                       }
    onReleased: mouse => {
                  if (mouse.button !== Qt.LeftButton)
                  return;
                  if (root.isSwiping) {
                    root.isSwiping = false;
                    const dismissDistance = root.useVerticalSwipe ? Math.abs(root.swipeOffsetY) : Math.abs(root.swipeOffset);
                    const threshold = root.useVerticalSwipe ? root.verticalSwipeDismissThreshold : root.swipeDismissThreshold;
                    if (dismissDistance >= threshold) {
                      root.hide();
                    } else {
                      root.swipeOffset = 0;
                      root.swipeOffsetY = 0;
                    }
                    return;
                  }
                  root.hide();
                }
    onCanceled: {
      root.isSwiping = false;
      root.swipeOffset = 0;
      root.swipeOffsetY = 0;
    }
    cursorShape: Qt.PointingHandCursor
  }

  RowLayout {
    id: contentLayout
    anchors.fill: background
    anchors.topMargin: Style.marginM
    anchors.bottomMargin: Style.marginM
    anchors.leftMargin: Style.margin2M
    anchors.rightMargin: Style.margin2M
    spacing: Style.marginL

    // Icon
    NIcon {
      icon: if (root.icon !== "") {
              return root.icon;
            } else if (type === "warning") {
              return "toast-warning";
            } else if (type === "error") {
              return "toast-error";
            } else {
              return "toast-notice";
            }
      color: {
        switch (type) {
        case "warning":
          return Color.mPrimary;
        case "error":
          return Color.mError;
        default:
          return Color.mOnSurface;
        }
      }
      pointSize: Style.fontSizeXXL * 1.5
      Layout.alignment: Qt.AlignVCenter
    }

    // Label and description
    ColumnLayout {
      spacing: Style.marginXXS
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter

      NText {
        Layout.fillWidth: true
        text: root.title
        color: Color.mOnSurface
        pointSize: Style.fontSizeL
        font.weight: Style.fontWeightBold
        wrapMode: Text.WordWrap
        visible: text.length > 0
      }

      NText {
        Layout.fillWidth: true
        text: root.description
        color: Color.mOnSurface
        pointSize: Style.fontSizeM
        wrapMode: Text.WordWrap
        visible: text.length > 0
      }

      // Action button
      NButton {
        text: root.actionLabel
        visible: root.actionLabel.length > 0 && root.actionCallback !== null
        Layout.topMargin: Style.marginXS
        fontSize: Style.fontSizeS
        backgroundColor: Color.mPrimary
        textColor: hovered ? Color.mOnHover : Color.mOnPrimary
        hoverColor: Color.mHover
        outlined: false
        implicitHeight: 24

        onEntered: root.hoverCount++
        onExited: root.hoverCount--

        onClicked: {
          if (root.actionCallback) {
            root.actionCallback();
            root.hide();
          }
        }
      }
    }
  }

  function show(msgTitle, msgDescription, msgIcon, msgType, msgDuration, msgActionLabel, msgActionCallback) {
    // Stop all timers first
    progressAnimation.stop();
    hideAnimation.stop();

    title = msgTitle;
    description = msgDescription || "";
    icon = msgIcon || "";
    type = msgType || "notice";
    duration = msgDuration || 3000;
    actionLabel = msgActionLabel || "";
    actionCallback = msgActionCallback || null;

    visible = true;
    opacity = 1.0;
    scale = 1.0;
    progress = 1.0;
    hoverCount = 0;
    isSwiping = false;
    swipeOffset = 0;
    swipeOffsetY = 0;

    // Configure and start animation
    progressAnimation.duration = duration;
    progressAnimation.from = 1.0;
    progressAnimation.to = 0.0;
    progressAnimation.restart();
  }

  function hide() {
    progressAnimation.stop();
    isSwiping = false;
    swipeOffset = 0;
    swipeOffsetY = 0;
    opacity = 0;
    scale = initialScale;
    hideAnimation.restart();
  }

  function hideImmediately() {
    hideAnimation.stop();
    progressAnimation.stop();
    isSwiping = false;
    swipeOffset = 0;
    swipeOffsetY = 0;
    opacity = 0;
    scale = initialScale;
    root.hidden();
  }
}
