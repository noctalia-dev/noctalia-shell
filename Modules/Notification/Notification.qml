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

  delegate: Loader {
    id: root

    required property ShellScreen modelData
    property real scaling: ScalingService.getScreenScale(modelData)

    Connections {
      target: ScalingService
      function onScaleChanged(screenName, newScale) {
        if (modelData && screenName === modelData.name) {
          scaling = newScale
        }
      }
    }

    // Access the notification model from the service - UPDATED NAME
    property ListModel notificationModel: NotificationService.activeList

    // If no notification display activated in settings, then show them all
    active: Settings.isLoaded && modelData && (notificationModel.count > 0) ? (Settings.data.notifications.monitors.includes(modelData.name) || (Settings.data.notifications.monitors.length === 0)) : false

    visible: (notificationModel.count > 0)

    sourceComponent: PanelWindow {
      screen: modelData
      color: Color.transparent

      // Position based on bar location - always at top
      anchors.top: true
      anchors.right: Settings.data.bar.position === "right" || Settings.data.bar.position === "top" || Settings.data.bar.position === "bottom"
      anchors.left: Settings.data.bar.position === "left"

      margins.top: {
        switch (Settings.data.bar.position) {
        case "top":
          return (Style.barHeight + Style.marginM) * scaling + (Settings.data.bar.floating ? Settings.data.bar.marginVertical * Style.marginXL * scaling : 0)
        default:
          return Style.marginM * scaling
        }
      }

      margins.bottom: {
        switch (Settings.data.bar.position) {
        case "bottom":
          return (Style.barHeight + Style.marginM) * scaling + (Settings.data.bar.floating ? Settings.data.bar.marginVertical * Style.marginXL * scaling : 0)
        default:
          return 0
        }
      }

      margins.left: {
        switch (Settings.data.bar.position) {
        case "left":
          return (Style.barHeight + Style.marginM) * scaling + (Settings.data.bar.floating ? Settings.data.bar.marginHorizontal * Style.marginXL * scaling : 0)
        default:
          return 0
        }
      }

      margins.right: {
        switch (Settings.data.bar.position) {
        case "right":
          return (Style.barHeight + Style.marginM) * scaling + (Settings.data.bar.floating ? Settings.data.bar.marginHorizontal * Style.marginXL * scaling : 0)
        case "top":
        case "bottom":
          return Style.marginM * scaling
        default:
          return 0
        }
      }

      implicitWidth: 360 * scaling
      implicitHeight: notificationStack.implicitHeight
      WlrLayershell.exclusionMode: ExclusionMode.Ignore

      // Connect to animation signal from service - UPDATED TO USE ID
      Component.onCompleted: {
        NotificationService.animateAndRemove.connect(function (notificationId, index) {
          // Find the delegate by notification ID
          var delegate = null
          if (notificationStack && notificationStack.children && notificationStack.children.length > 0) {
            for (var i = 0; i < notificationStack.children.length; i++) {
              var child = notificationStack.children[i]
              if (child && child.notificationId === notificationId) {
                delegate = child
                break
              }
            }
          }

          // Fallback to index if ID lookup failed
          if (!delegate && notificationStack && notificationStack.children && notificationStack.children[index]) {
            delegate = notificationStack.children[index]
          }

          if (delegate && delegate.animateOut) {
            delegate.animateOut()
          } else {
            // Force removal without animation as fallback
            NotificationService.dismissActiveNotification(notificationId)
          }
        })
      }

      // Main notification container
      ColumnLayout {
        id: notificationStack
        anchors.top: parent.top
        anchors.right: (Settings.data.bar.position === "right" || Settings.data.bar.position === "top" || Settings.data.bar.position === "bottom") ? parent.right : undefined
        anchors.left: Settings.data.bar.position === "left" ? parent.left : undefined
        spacing: Style.marginS * scaling
        width: 360 * scaling
        visible: true

        // Multiple notifications display
        Repeater {
          model: notificationModel
          delegate: Rectangle {
            // Store the notification ID for reference
            property string notificationId: model.id

            Layout.preferredWidth: 360 * scaling
            Layout.preferredHeight: notificationLayout.implicitHeight + (Style.marginL * 2 * scaling)
            Layout.maximumHeight: Layout.preferredHeight
            clip: true
            radius: Style.radiusL * scaling
            border.color: Color.mOutline
            border.width: Math.max(1, Style.borderS * scaling)
            color: Color.mSurface

            // Animation properties
            property real scaleValue: 0.8
            property real opacityValue: 0.0
            property bool isRemoving: false

            // Right-click to dismiss
            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.RightButton
              onClicked: {
                if (mouse.button === Qt.RightButton) {
                  animateOut()
                }
              }
            }

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
                // Use the new API method with notification ID
                NotificationService.dismissActiveNotification(notificationId)
              }
            }

            // Check if this notification is being removed
            onIsRemovingChanged: {
              if (isRemoving) {
                removalTimer.start()
              }
            }

            // Animation behaviors
            Behavior on scale {
              NumberAnimation {
                duration: Style.animationSlow
                easing.type: Easing.OutExpo
              }
            }

            Behavior on opacity {
              NumberAnimation {
                duration: Style.animationNormal
                easing.type: Easing.OutQuad
              }
            }

            ColumnLayout {
              id: notificationLayout
              anchors.fill: parent
              anchors.margins: Style.marginM * scaling
              anchors.rightMargin: (Style.marginM + 32) * scaling // Leave space for close button
              spacing: Style.marginM * scaling

              // Main content section
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginM * scaling

                ColumnLayout {
                  // For real-time notification always show the original image
                  // as the cached version is most likely still processing.
                  NImageCircled {
                    Layout.preferredWidth: 40 * scaling
                    Layout.preferredHeight: 40 * scaling
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 30 * scaling
                    imagePath: model.originalImage || ""
                    borderColor: Color.transparent
                    borderWidth: 0
                    fallbackIcon: "bell"
                    fallbackIconSize: 24 * scaling
                  }
                  Item {
                    Layout.fillHeight: true
                  }
                }

                // Text content
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginS * scaling

                  // Header section with app name and timestamp
                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginS * scaling

                    Rectangle {
                      Layout.preferredWidth: 6 * scaling
                      Layout.preferredHeight: 6 * scaling
                      radius: Style.radiusXS * scaling
                      color: {
                        if (model.urgency === NotificationUrgency.Critical || model.urgency === 2)
                          return Color.mError
                        else if (model.urgency === NotificationUrgency.Low || model.urgency === 0)
                          return Color.mOnSurface
                        else
                          return Color.mPrimary
                      }
                      Layout.alignment: Qt.AlignVCenter
                    }

                    NText {
                      text: `${model.appName || "Unknown App"} · ${Time.formatRelativeTime(model.timestamp)}`
                      color: Color.mSecondary
                      font.pointSize: Style.fontSizeXS * scaling
                    }

                    Item {
                      Layout.fillWidth: true
                    }
                  }

                  NText {
                    text: model.summary || "No summary"
                    font.pointSize: Style.fontSizeL * scaling
                    font.weight: Style.fontWeightMedium
                    color: Color.mOnSurface
                    textFormat: Text.PlainText
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    Layout.fillWidth: true
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    visible: text.length > 0
                  }

                  NText {
                    text: model.body || ""
                    font.pointSize: Style.fontSizeM * scaling
                    color: Color.mOnSurface
                    textFormat: Text.PlainText
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    Layout.fillWidth: true
                    maximumLineCount: 5
                    elide: Text.ElideRight
                    visible: text.length > 0
                  }

                  // Notification actions
                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginS * scaling
                    Layout.topMargin: Style.marginM * scaling

                    // Store the notification ID for access in button delegates
                    property string parentNotificationId: notificationId

                    // Parse actions from JSON string
                    property var parsedActions: {
                      try {
                        return model.actionsJson ? JSON.parse(model.actionsJson) : []
                      } catch (e) {
                        return []
                      }
                    }
                    visible: parsedActions.length > 0

                    Repeater {
                      model: parent.parsedActions

                      delegate: NButton {
                        property var actionData: modelData

                        text: {
                          var actionText = actionData.text || "Open"
                          // If text contains comma, take the part after the comma (the display text)
                          if (actionText.includes(",")) {
                            return actionText.split(",")[1] || actionText
                          }
                          return actionText
                        }
                        fontSize: Style.fontSizeS * scaling
                        backgroundColor: Color.mPrimary
                        textColor: hovered ? Color.mOnTertiary : Color.mOnPrimary
                        hoverColor: Color.mTertiary
                        outlined: false
                        Layout.preferredHeight: 24 * scaling
                        onClicked: {
                          NotificationService.invokeAction(parent.parentNotificationId, actionData.identifier)
                        }
                      }
                    }

                    // Spacer to push buttons to the left
                    Item {
                      Layout.fillWidth: true
                    }
                  }
                }
              }
            }

            // Close button positioned absolutely
            NIconButton {
              icon: "close"
              tooltipText: "Close"
              baseSize: Style.baseWidgetSize * 0.6
              anchors.top: parent.top
              anchors.topMargin: Style.marginM * scaling
              anchors.right: parent.right
              anchors.rightMargin: Style.marginM * scaling

              onClicked: {
                animateOut()
              }
            }
          }
        }
      }
    }
  }
}
