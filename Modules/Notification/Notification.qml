import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs.Commons
import qs.Services
import qs.Widgets

// Simple notification popup - displays multiple notifications
Variants {
  model: Quickshell.screens

  PanelWindow {
    id: root

    required property ShellScreen modelData
    readonly property real scaling: ScalingService.scale(screen)
    screen: modelData

    // Access the notification model from the service
    property ListModel notificationModel: NotificationService.notificationModel

    // Track notifications being removed for animation
    property var removingNotifications: ({})

    color: Color.transparent

    // If no notification display activated in settings, then show them all
    visible: modelData ? (Settings.data.notifications.monitors.includes(modelData.name)
                          || (Settings.data.notifications.monitors.length === 0))
                         && (NotificationService.notificationModel.count > 0) : false

    // Position based on bar location
    anchors.top: Settings.data.bar.position === "top"
    anchors.bottom: Settings.data.bar.position === "bottom"
    anchors.right: true
    margins.top: Settings.data.bar.position === "top" ? (Style.barHeight + Style.marginM) * scaling : 0
    margins.bottom: Settings.data.bar.position === "bottom" ? (Style.barHeight + Style.marginM) * scaling : 0
    margins.right: Style.marginM * scaling
    implicitWidth: 360 * scaling
    implicitHeight: Math.min(notificationStack.implicitHeight, (NotificationService.maxVisible * 120) * scaling)
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    // Connect to animation signal from service
    Component.onCompleted: {
      NotificationService.animateAndRemove.connect(function (notification, index) {
        // Prefer lookup by identity to avoid index mismatches
        var delegate = null
        if (notificationStack.children && notificationStack.children.length > 0) {
          for (var i = 0; i < notificationStack.children.length; i++) {
            var child = notificationStack.children[i]
            if (child && child.model && child.model.rawNotification === notification) {
              delegate = child
              break
            }
          }
        }

        // Fallback to index if identity lookup failed
        if (!delegate && notificationStack.children && notificationStack.children[index]) {
          delegate = notificationStack.children[index]
        }

        if (delegate && delegate.animateOut) {
          delegate.animateOut()
        } else {
          // As a last resort, force-remove without animation to avoid stuck popups
          NotificationService.forceRemoveNotification(notification)
        }
      })
    }

    // Main notification container
    Column {
      id: notificationStack
      // Position based on bar location
      anchors.top: Settings.data.bar.position === "top" ? parent.top : undefined
      anchors.bottom: Settings.data.bar.position === "bottom" ? parent.bottom : undefined
      anchors.right: parent.right
      spacing: Style.marginS * scaling
      width: 360 * scaling
      visible: true

      // Multiple notifications display
      Repeater {
        model: notificationModel
        delegate: Rectangle {
          width: 360 * scaling
          height: Math.max(80 * scaling, contentColumn.implicitHeight + (Style.marginM * 2 * scaling))
          clip: true
          radius: Style.radiusM * scaling
          border.color: Color.mPrimary
          border.width: Math.max(1, Style.borderS * scaling)
          color: Color.mSurface

          // Capture raw notification once for nested bindings
          property var raw: model.rawNotification

          // Animation properties
          property real scaleValue: 0.8
          property real opacityValue: 0.0
          property bool isRemoving: false

          // Scale and fade-in animation
          scale: scaleValue
          opacity: opacityValue

          // Animate in when the item is created
          Component.onCompleted: {
            scaleValue = 1.0
            opacityValue = 1.0
          }

          // Animate out when being removed
          function animateOut() {
            isRemoving = true
            scaleValue = 0.8
            opacityValue = 0.0
          }

          // Timer for delayed removal after animation
          Timer {
            id: removalTimer
            interval: Style.animationSlow
            repeat: false
            onTriggered: {
              NotificationService.forceRemoveNotification(model.rawNotification)
            }
          }

          // Check if this notification is being removed
          onIsRemovingChanged: {
            if (isRemoving) {
              // Remove from model after animation completes
              removalTimer.start()
            }
          }

          // Animation behaviors
          Behavior on scale {
            NumberAnimation {
              duration: Style.animationSlow
              easing.type: Easing.OutExpo
              //easing.type: Easing.OutBack   looks better but notification get clipped on all sides
            }
          }

          Behavior on opacity {
            NumberAnimation {
              duration: Style.animationNormal
              easing.type: Easing.OutQuad
            }
          }

          Column {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: Style.marginM * scaling
            spacing: Style.marginS * scaling

            RowLayout {
              spacing: Style.marginS * scaling
              NText {
                text: (model.appName || model.desktopEntry) || "Unknown App"
                color: Color.mSecondary
                font.pointSize: Style.fontSizeXS * scaling
              }
              Rectangle {
                width: 6 * scaling
                height: 6 * scaling
                radius: Style.radiusXS * scaling
                color: (model.urgency === NotificationUrgency.Critical) ? Color.mError : (model.urgency === NotificationUrgency.Low) ? Color.mOnSurface : Color.mPrimary
                Layout.alignment: Qt.AlignVCenter
              }
              Item {
                Layout.fillWidth: true
              }
              NText {
                text: NotificationService.formatTimestamp(model.timestamp)
                color: Color.mOnSurface
                font.pointSize: Style.fontSizeXS * scaling
              }
            }

            NText {
              text: model.summary || "No summary"
              font.pointSize: Style.fontSizeL * scaling
              font.weight: Style.fontWeightBold
              color: Color.mOnSurface
              wrapMode: Text.Wrap
              width: 300 * scaling
              maximumLineCount: 3
              elide: Text.ElideRight
            }

            NText {
              text: model.body || ""
              font.pointSize: Style.fontSizeXS * scaling
              color: Color.mOnSurface
              wrapMode: Text.Wrap
              width: 300 * scaling
              maximumLineCount: 5
              elide: Text.ElideRight
            }

            // Actions row (uses NPill for clean, clickable chips)
            Flow {
              id: actionsFlow
              width: 300 * scaling
              spacing: Style.marginXS * scaling
              visible: actionsRepeater.count > 0

              Repeater {
                id: actionsRepeater
                // The actions list comes from the raw notification (list<NotificationAction>)
                model: (raw && raw.actions) ? raw.actions : []

                delegate: NPill {
                  id: actionPill
                  // Always shown as a solid pill; uses shell colors
                  sizeMultiplier: 0.8
                  forceShown: true
                  text: (modelData && modelData.text) ? modelData.text : ((modelData && modelData.label) ? modelData.label : ((modelData && modelData.identifier) ? modelData.identifier : ""))
                  // Hover state to swap colors
                  property bool hovering: false
                  pillColor: hovering ? Color.mPrimary : Color.mSurfaceVariant
                  textColor: hovering ? Color.mOnPrimary : Color.mOnSurface
                  // Place the action icon on the left for better readability here
                  iconSide: "left"
                  // Pick an icon for common action identifiers/labels
                  icon: {
                    function pickIcon(s) {
                      if (!s) return ""
                      s = ("" + s).toLowerCase()
                      if (s.includes("open") || s === "default" || s.includes("view")) return "open_in_new"
                      if (s.includes("dismiss") || s.includes("close") || s.includes("cancel")) return "close"
                      if (s.includes("reply")) return "reply"
                      if (s.includes("snooze")) return "snooze"
                      if (s.includes("accept") || s.includes("ok") || s.includes("yes")) return "check"
                      if (s.includes("deny") || s.includes("no")) return "close"
                      return ""
                    }
                    const id = (modelData && (modelData.identifier || modelData.id)) ? (modelData.identifier || modelData.id) : ""
                    const label = (modelData && (modelData.text || modelData.label)) ? (modelData.text || modelData.label) : ""
                    return pickIcon(id) || pickIcon(label)
                  }

                  // Pointer cursor + drive hover color without stealing clicks
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    cursorShape: Qt.PointingHandCursor
                    onEntered: actionPill.hovering = true
                    onExited: actionPill.hovering = false
                  }

                  onClicked: {
                    try {
                      if (modelData && modelData.invoke) {
                        modelData.invoke()
                        // Let NotificationAction decide dismissal; service will animate closed via closed signal
                      }
                    } catch (e) {
                      Logger.error("Notifications", "Action invoke failed:", e)
                    }
                  }
                }
              }
            }
          }

          NIconButton {
            icon: "close"
            tooltipText: "Close"
            sizeMultiplier: 0.8
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Style.marginS * scaling

            onClicked: {
              animateOut()
            }
          }
        }
      }
    }
  }
}
