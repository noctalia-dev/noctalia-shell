import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Services.System
import qs.Widgets

// Simple notification popup - displays multiple notifications
Variants {
  // If no notification display activated in settings, then show them all
  model: Quickshell.screens.filter(screen => (Settings.data.notifications.monitors.includes(screen.name) || (Settings.data.notifications.monitors.length === 0)))

  delegate: Loader {
    id: root

    required property ShellScreen modelData

    property ListModel notificationModel: NotificationService.activeList

    // Always create window (but with 0x0 dimensions when no notifications)
    active: notificationModel.count > 0 || delayTimer.running

    // Keep loader active briefly after last notification to allow animations to complete
    Timer {
      id: delayTimer
      interval: Style.animationSlow + 200
      repeat: false
    }

    Connections {
      target: notificationModel
      function onCountChanged() {
        if (notificationModel.count === 0 && root.active) {
          delayTimer.restart();
        }
      }
    }

    sourceComponent: PanelWindow {
      id: notifWindow
      screen: modelData

      WlrLayershell.namespace: "noctalia-notifications-" + (screen?.name || "unknown")
      WlrLayershell.layer: (Settings.data.notifications?.overlayLayer) ? WlrLayer.Overlay : WlrLayer.Top
      WlrLayershell.exclusionMode: ExclusionMode.Ignore

      color: "transparent"

      // Make shadow area click-through, only notification content is clickable
      mask: Region {
        x: 0
        y: 0
        width: notifWindow.width
        height: notifWindow.height
        intersection: Intersection.Xor

        Region {
          // The clickable content area is inset by shadowPadding from all edges
          x: notifWindow.shadowPadding
          y: notifWindow.shadowPadding
          width: notifWindow.notifWidth
          height: Math.max(0, notifWindow.height - notifWindow.shadowPadding * 2)
          intersection: Intersection.Subtract
        }
      }

      // Parse location setting
      readonly property string location: Settings.data.notifications.location || "top_right"
      readonly property bool isTop: location.startsWith("top")
      readonly property bool isBottom: location.startsWith("bottom")
      readonly property bool isLeft: location.endsWith("_left")
      readonly property bool isRight: location.endsWith("_right")
      readonly property bool isCentered: location === "top" || location === "bottom"

      readonly property string barPos: Settings.getBarPositionForScreen(notifWindow.screen?.name)
      readonly property bool isFloating: Settings.data.bar.floating
      readonly property real barHeight: Style.getBarHeightForScreen(notifWindow.screen?.name)

      readonly property bool isFramed: Settings.data.bar.barType === "framed"
      readonly property real frameThickness: Settings.data.bar.frameThickness ?? 8

      readonly property int notifWidth: Math.round(440 * Style.uiScaleRatio)
      readonly property int shadowPadding: Style.shadowBlurMax + Style.marginL

      // Calculate bar and frame offsets for each edge separately
      readonly property int barOffsetTop: {
        if (barPos !== "top")
          return isFramed ? frameThickness : 0;
        const floatMarginV = isFloating ? Math.ceil(Settings.data.bar.marginVertical) : 0;
        return barHeight + floatMarginV;
      }

      readonly property int barOffsetBottom: {
        if (barPos !== "bottom")
          return isFramed ? frameThickness : 0;
        const floatMarginV = isFloating ? Math.ceil(Settings.data.bar.marginVertical) : 0;
        return barHeight + floatMarginV;
      }

      readonly property int barOffsetLeft: {
        if (barPos !== "left")
          return isFramed ? frameThickness : 0;
        const floatMarginH = isFloating ? Math.ceil(Settings.data.bar.marginHorizontal) : 0;
        return barHeight + floatMarginH;
      }

      readonly property int barOffsetRight: {
        if (barPos !== "right")
          return isFramed ? frameThickness : 0;
        const floatMarginH = isFloating ? Math.ceil(Settings.data.bar.marginHorizontal) : 0;
        return barHeight + floatMarginH;
      }

      // Anchoring
      anchors.top: isTop
      anchors.bottom: isBottom
      anchors.left: isLeft
      anchors.right: isRight

      // Margins for PanelWindow - only apply bar offset for the specific edge where the bar is
      margins.top: isTop ? barOffsetTop - shadowPadding + Style.marginM : 0
      margins.bottom: isBottom ? barOffsetBottom - shadowPadding : 0
      margins.left: isLeft ? barOffsetLeft - shadowPadding + Style.marginM : 0
      margins.right: isRight ? barOffsetRight - shadowPadding + Style.marginM : 0

      implicitWidth: notifWidth + shadowPadding * 2
      implicitHeight: notificationStack.implicitHeight + Style.marginL

      property var animateConnection: null

      Component.onCompleted: {
        animateConnection = function (notificationId) {
          var delegate = null;
          if (notificationRepeater) {
            for (var i = 0; i < notificationRepeater.count; i++) {
              var item = notificationRepeater.itemAt(i);
              if (item?.notificationId === notificationId) {
                delegate = item;
                break;
              }
            }
          }

          try {
            if (delegate && typeof delegate.animateOut === "function" && !delegate.isRemoving) {
              delegate.animateOut();
            }
          } catch (e) {
            // Service fallback if delegate is already invalid
            NotificationService.dismissActiveNotification(notificationId);
          }
        };

        NotificationService.animateAndRemove.connect(animateConnection);
      }

      Component.onDestruction: {
        if (animateConnection) {
          NotificationService.animateAndRemove.disconnect(animateConnection);
          animateConnection = null;
        }
      }

      ColumnLayout {
        id: notificationStack

        anchors {
          top: parent.isTop ? parent.top : undefined
          bottom: parent.isBottom ? parent.bottom : undefined
          left: parent.isLeft ? parent.left : undefined
          right: parent.isRight ? parent.right : undefined
          horizontalCenter: parent.isCentered ? parent.horizontalCenter : undefined
        }

        spacing: -notifWindow.shadowPadding * 2 + Style.marginM

        Behavior on implicitHeight {
          enabled: !Settings.data.general.animationDisabled
          SpringAnimation {
            spring: 2.0
            damping: 0.4
            epsilon: 0.01
            mass: 0.8
          }
        }

        Repeater {
          id: notificationRepeater
          model: notificationModel

          delegate: Item {
            id: card

            property string notificationId: model.id
            property var notificationData: model
            property int hoverCount: 0
            property bool isRemoving: false

            readonly property int animationDelay: index * 100
            readonly property int slideDistance: 300

            readonly property string animationType: Style.notificationAnimationType
            readonly property bool useSlide: Style.animHasSlide(animationType)
            readonly property bool useScale: Style.animHasScale(animationType)
            readonly property bool useFade: Style.animHasFade(animationType)
            readonly property bool useNone: animationType === "none"
            readonly property real animationScaleValue: Style.animScaleValue(animationType, 0.8)

            Layout.preferredWidth: notifWidth + notifWindow.shadowPadding * 2
            Layout.preferredHeight: notificationContent.implicitHeight + Style.marginXL + notifWindow.shadowPadding * 2
            Layout.maximumHeight: Layout.preferredHeight

            property real scaleValue: 0.8
            property real opacityValue: 0.0
            property real slideOffset: 0

            scale: scaleValue
            opacity: opacityValue
            transform: Translate {
              y: card.slideOffset
            }

            readonly property real slideInOffset: notifWindow.isTop ? -slideDistance : slideDistance
            readonly property real slideOutOffset: slideInOffset

            // Background with border
            Rectangle {
              id: cardBackground
              anchors.fill: parent
              anchors.margins: notifWindow.shadowPadding
              radius: Style.radiusL
              border.color: Qt.alpha(Color.mOutline, Settings.data.notifications.backgroundOpacity || 1.0)
              border.width: Style.borderS
              color: Qt.alpha(Color.mSurface, Settings.data.notifications.backgroundOpacity || 1.0)

              // Progress bar
              Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 2
                color: "transparent"

                Rectangle {
                  id: progressBar
                  readonly property real progressWidth: cardBackground.width - (2 * cardBackground.radius)
                  height: parent.height
                  x: cardBackground.radius + (progressWidth * (1 - model.progress)) / 2
                  width: progressWidth * model.progress

                  color: {
                    var baseColor = model.urgency === 2 ? Color.mError : model.urgency === 0 ? Color.mOnSurface : Color.mPrimary;
                    return Qt.alpha(baseColor, Settings.data.notifications.backgroundOpacity || 1.0);
                  }

                  antialiasing: true

                  Behavior on width {
                    enabled: !card.isRemoving
                    NumberAnimation {
                      duration: 100
                      easing.type: Easing.Linear
                    }
                  }

                  Behavior on x {
                    enabled: !card.isRemoving
                    NumberAnimation {
                      duration: 100
                      easing.type: Easing.Linear
                    }
                  }
                }
              }
            }

            NDropShadow {
              anchors.fill: cardBackground
              source: cardBackground
              autoPaddingEnabled: true
            }

            // Hover handling
            onHoverCountChanged: {
              if (hoverCount > 0) {
                resumeTimer.stop();
                NotificationService.pauseTimeout(notificationId);
              } else {
                resumeTimer.start();
              }
            }

            Timer {
              id: resumeTimer
              interval: 50
              repeat: false
              onTriggered: {
                if (hoverCount === 0) {
                  NotificationService.resumeTimeout(notificationId);
                }
              }
            }

            // Right-click to dismiss
            MouseArea {
              anchors.fill: cardBackground
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              hoverEnabled: true
              onEntered: card.hoverCount++
              onExited: card.hoverCount--
              onClicked: mouse => {
                           if (mouse.button === Qt.RightButton) {
                             card.animateOut();
                           } else if (mouse.button === Qt.LeftButton) {
                             var actions = model.actionsJson ? JSON.parse(model.actionsJson) : [];
                             var hasDefault = actions.some(function (a) {
                               return a.identifier === "default";
                             });
                             if (hasDefault) {
                               card.animateOut();
                               deferredActionTimer.actionId = "default";
                               deferredActionTimer.start();
                             }
                           }
                         }
            }
            // Animation setup
            function triggerEntryAnimation() {
              animInDelayTimer.stop();
              removalTimer.stop();
              resumeTimer.stop();
              isRemoving = false;
              hoverCount = 0;
              if (useNone) {
                slideOffset = 0;
                scaleValue = 1.0;
                opacityValue = 1.0;
                return;
              }

              // Set initial values based on animation type
              slideOffset = useSlide ? slideInOffset : 0;
              scaleValue = useScale ? animationScaleValue : 1.0;
              opacityValue = useFade ? 0.0 : 1.0;
              animInDelayTimer.interval = animationDelay;
              animInDelayTimer.start();
            }

            Component.onCompleted: triggerEntryAnimation()

            onNotificationIdChanged: triggerEntryAnimation()

            Timer {
              id: animInDelayTimer
              interval: 0
              repeat: false
              onTriggered: {
                if (card.isRemoving)
                  return;
                slideOffset = 0;
                scaleValue = 1.0;
                opacityValue = 1.0;
              }
            }

            function animateOut() {
              if (isRemoving)
                return;
              animInDelayTimer.stop();
              resumeTimer.stop();
              isRemoving = true;
              if (!useNone) {
                // Set exit values based on animation type
                slideOffset = useSlide ? slideOutOffset : 0;
                scaleValue = useScale ? animationScaleValue : 1.0;
                opacityValue = useFade ? 0.0 : 1.0;
              }
            }

            Timer {
              id: removalTimer
              interval: Style.animationSlow
              repeat: false
              onTriggered: {
                NotificationService.dismissActiveNotification(notificationId);
              }
            }

            Timer {
              id: deferredActionTimer
              interval: 50
              property string actionId: ""
              property bool isHistoryRemoval: false
              onTriggered: {
                if (isHistoryRemoval) {
                  NotificationService.removeFromHistory(notificationId);
                } else {
                  NotificationService.invokeAction(notificationId, actionId);
                }
              }
            }

            onIsRemovingChanged: {
              if (isRemoving) {
                removalTimer.start();
              }
            }

            Behavior on scale {
              enabled: !card.useNone && card.useScale
              SpringAnimation {
                spring: 3
                damping: 0.4
                epsilon: 0.01
                mass: 0.8
              }
            }

            Behavior on opacity {
              enabled: !card.useNone && card.useFade
              NumberAnimation {
                duration: Style.animationNormal
                easing.type: Style.easingTypeDefault
                easing.bezierCurve: Style.easingCurveDefault
              }
            }

            Behavior on slideOffset {
              enabled: !card.useNone && card.useSlide
              SpringAnimation {
                spring: 2.5
                damping: 0.3
                epsilon: 0.01
                mass: 0.6
              }
            }

            // Content
            ColumnLayout {
              id: notificationContent
              anchors.fill: cardBackground
              anchors.margins: Style.marginM
              spacing: Style.marginM

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginL
                Layout.leftMargin: Style.marginM
                Layout.rightMargin: Style.marginM
                Layout.topMargin: Style.marginM
                Layout.bottomMargin: Style.marginM

                NImageRounded {
                  Layout.preferredWidth: Math.round(40 * Style.uiScaleRatio)
                  Layout.preferredHeight: Math.round(40 * Style.uiScaleRatio)
                  Layout.alignment: Qt.AlignVCenter
                  radius: Math.min(Style.radiusL, Layout.preferredWidth / 2)
                  imagePath: model.originalImage || ""
                  borderColor: "transparent"
                  borderWidth: 0
                  fallbackIcon: "bell"
                  fallbackIconSize: 24
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginS

                  // Header with urgency indicator
                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginS

                    Rectangle {
                      Layout.preferredWidth: 6
                      Layout.preferredHeight: 6
                      Layout.alignment: Qt.AlignVCenter
                      radius: Style.radiusXS
                      color: model.urgency === 2 ? Color.mError : model.urgency === 0 ? Color.mOnSurface : Color.mPrimary
                    }

                    NText {
                      text: model.appName || "Unknown App"
                      pointSize: Style.fontSizeXS
                      font.weight: Style.fontWeightBold
                      color: Color.mSecondary
                    }

                    NText {
                      textFormat: Text.PlainText
                      text: " " + Time.formatRelativeTime(model.timestamp)
                      pointSize: Style.fontSizeXXS
                      color: Color.mOnSurfaceVariant
                      Layout.alignment: Qt.AlignBottom
                    }

                    Item {
                      Layout.fillWidth: true
                    }
                  }

                  NText {
                    text: model.summary || I18n.tr("common.no-summary")
                    pointSize: Style.fontSizeM
                    font.weight: Style.fontWeightMedium
                    color: Color.mOnSurface
                    textFormat: Text.PlainText
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    visible: text.length > 0
                    Layout.fillWidth: true
                    Layout.rightMargin: Style.marginM
                  }

                  NText {
                    text: model.body || ""
                    pointSize: Style.fontSizeM
                    color: Color.mOnSurface
                    textFormat: Text.PlainText
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere

                    maximumLineCount: 5
                    elide: Text.ElideRight
                    visible: text.length > 0
                    Layout.fillWidth: true
                    Layout.rightMargin: Style.marginXL
                  }

                  // Actions
                  Flow {
                    Layout.fillWidth: true
                    spacing: Style.marginS
                    Layout.topMargin: Style.marginM
                    flow: Flow.LeftToRight

                    property string parentNotificationId: notificationId
                    property var parsedActions: {
                      try {
                        return model.actionsJson ? JSON.parse(model.actionsJson) : [];
                      } catch (e) {
                        return [];
                      }
                    }
                    visible: parsedActions.length > 0

                    Repeater {
                      model: parent.parsedActions

                      delegate: NButton {
                        property var actionData: modelData

                        onEntered: card.hoverCount++
                        onExited: card.hoverCount--

                        text: {
                          var actionText = actionData.text || "Open";
                          if (actionText.includes(",")) {
                            return actionText.split(",")[1] || actionText;
                          }
                          return actionText;
                        }
                        fontSize: Style.fontSizeS
                        backgroundColor: Color.mPrimary
                        textColor: hovered ? Color.mOnHover : Color.mOnPrimary
                        hoverColor: Color.mHover
                        outlined: false
                        implicitHeight: 24
                        onClicked: {
                          card.animateOut();
                          deferredActionTimer.actionId = actionData.identifier;
                          deferredActionTimer.isHistoryRemoval = false;
                          deferredActionTimer.start();
                        }
                      }
                    }
                  }
                }
              }
            }

            // Close button
            NIconButton {
              icon: "close"
              tooltipText: I18n.tr("common.close")
              baseSize: Style.baseWidgetSize * 0.6
              anchors.top: cardBackground.top
              anchors.topMargin: Style.marginM
              anchors.right: cardBackground.right
              anchors.rightMargin: Style.marginM

              onClicked: {
                card.animateOut();
                deferredActionTimer.isHistoryRemoval = true;
                deferredActionTimer.start();
              }
            }
          }
        }
      }
    }
  }
}
