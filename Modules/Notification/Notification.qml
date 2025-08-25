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

          readonly property var actionsModel: model.rawNotification ? model.rawNotification.actions : null

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

            // Actions row (if any)
            RowLayout {
              id: actionsRow
              spacing: Style.marginS * scaling
              visible: !!actionsModel && ((actionsModel.count !== undefined ? actionsModel.count : (actionsModel.length !== undefined ? actionsModel.length : 0)) > 0)

              Repeater {
                id: actionsRepeater
                model: actionsModel ? (actionsModel.count !== undefined ? actionsModel.count : (actionsModel.length !== undefined ? actionsModel.length : 0)) : 0

                delegate: NPill {
                  readonly property var actionObj: actionsModel && (actionsModel.get ? actionsModel.get(index) : actionsModel[index])

                  text: (actionObj && (actionObj.text || actionObj.identifier)) || "Action"
                  sizeMultiplier: 0.7
                  forceOpen: true
                  pillColor: Color.mPrimary
                  textColor: Color.mOnPrimary

                  onClicked: {
                    actionObj && actionObj.invoke && actionObj.invoke()
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
