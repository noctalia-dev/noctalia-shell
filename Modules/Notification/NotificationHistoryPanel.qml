import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs.Commons
import qs.Services
import qs.Widgets

// Loader for Notification History panel
NLoader {
  id: root

  content: Component {
    NPanel {
      id: notificationPanel

      // Override hide function to animate first
      function hide() {
        // Start hide animation
        notificationRect.scaleValue = 0.8
        notificationRect.opacityValue = 0.0

        // Hide after animation completes
        hideTimer.start()
      }

      Connections {
        target: notificationPanel
        ignoreUnknownSignals: true
        function onDismissed() {
          // Start hide animation
          notificationRect.scaleValue = 0.8
          notificationRect.opacityValue = 0.0

          // Hide after animation completes
          hideTimer.start()
        }
      }

      // Also handle visibility changes from external sources
      onVisibleChanged: {
        if (!visible && notificationRect.opacityValue > 0) {
          // Start hide animation
          notificationRect.scaleValue = 0.8
          notificationRect.opacityValue = 0.0

          // Hide after animation completes
          hideTimer.start()
        }
      }

      // Timer to hide panel after animation
      Timer {
        id: hideTimer
        interval: Style.animationSlow
        repeat: false
        onTriggered: {
          notificationPanel.visible = false
          notificationPanel.dismissed()
        }
      }

      WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

      Rectangle {
        id: notificationRect
        color: Color.mSurface
        radius: Style.radiusLarge * scaling
        border.color: Color.mOutlineVariant
        border.width: Math.max(1, Style.borderThin * scaling)
        width: 400 * scaling
        height: 500 * scaling
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Style.marginTiny * scaling
        anchors.rightMargin: Style.marginTiny * scaling
        clip: true

        // Animation properties
        property real scaleValue: 0.8
        property real opacityValue: 0.0

        scale: scaleValue
        opacity: opacityValue

        // Animate in when component is completed
        Component.onCompleted: {
          scaleValue = 1.0
          opacityValue = 1.0
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
          anchors.fill: parent
          anchors.margins: Style.marginLarge * scaling
          spacing: Style.marginMedium * scaling

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginMedium * scaling

            NIcon {
              text: "notifications"
              font.pointSize: Style.fontSizeXL * scaling
              color: Color.mPrimary
            }

            NText {
              text: "Notification History"
              font.pointSize: Style.fontSizeLarge * scaling
              font.bold: true
              color: Color.mOnSurface
              Layout.fillWidth: true
            }

            NIconButton {
              icon: "delete"
              tooltipText: "Clear History"
              sizeMultiplier: 0.8
              onClicked: NotificationService.clearHistory()
            }

            NIconButton {
              icon: "close"
              tooltipText: "Close"
              sizeMultiplier: 0.8
              onClicked: {
                notificationPanel.hide()
              }
            }
          }

          NDivider {}

          // Empty state when no notifications
          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: NotificationService.historyModel.count === 0

            ColumnLayout {
              anchors.centerIn: parent
              spacing: Style.marginMedium * scaling

              NIcon {
                text: "notifications_off"
                font.pointSize: Style.fontSizeXXL * scaling
                color: Color.mOnSurfaceVariant
                Layout.alignment: Qt.AlignHCenter
              }

              NText {
                text: "No notifications"
                font.pointSize: Style.fontSizeLarge * scaling
                color: Color.mOnSurfaceVariant
                Layout.alignment: Qt.AlignHCenter
              }

              NText {
                text: "Notifications will appear here when you receive them"
                font.pointSize: Style.fontSizeNormal * scaling
                color: Color.mOnSurfaceVariant
                Layout.alignment: Qt.AlignHCenter
              }
            }
          }

          ListView {
            id: notificationList
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: NotificationService.historyModel
            spacing: Style.marginMedium * scaling
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            visible: NotificationService.historyModel.count > 0

            delegate: Rectangle {
              width: notificationList ? (notificationList.width - 20) : 380 * scaling
              height: Math.max(80, notificationContent.height + 30)
              radius: Style.radiusMedium * scaling
              color: notificationMouseArea.containsMouse ? Color.mPrimary : Color.mSurfaceVariant

              RowLayout {
                anchors {
                  fill: parent
                  margins: Style.marginMedium * scaling
                }
                spacing: Style.marginMedium * scaling

                // Notification content
                Column {
                  id: notificationContent
                  Layout.fillWidth: true
                  Layout.alignment: Qt.AlignVCenter
                  spacing: Style.marginTiniest * scaling

                  NText {
                    text: (summary || "No summary").substring(0, 100)
                    font.pointSize: Style.fontSizeMedium * scaling
                    font.weight: Font.Medium
                    color: notificationMouseArea.containsMouse ? Color.mSurface : Color.mOnSurface
                    wrapMode: Text.Wrap
                    width: parent.width - 60
                    maximumLineCount: 2
                    elide: Text.ElideRight
                  }

                  NText {
                    text: (body || "").substring(0, 150)
                    font.pointSize: Style.fontSizeSmall * scaling
                    color: notificationMouseArea.containsMouse ? Color.mSurface : Color.mOnSurface
                    wrapMode: Text.Wrap
                    width: parent.width - 60
                    maximumLineCount: 3
                    elide: Text.ElideRight
                  }

                  NText {
                    text: NotificationService.formatTimestamp(timestamp)
                    font.pointSize: Style.fontSizeSmall * scaling
                    color: notificationMouseArea.containsMouse ? Color.mSurface : Color.mOnSurface
                  }
                }

                // Trash icon button
                NIconButton {
                  icon: "delete"
                  tooltipText: "Delete Notification"
                  sizeMultiplier: 0.7

                  onClicked: {
                    Logger.log("NotificationHistory", "Removing notification:", summary)
                    NotificationService.historyModel.remove(index)
                    NotificationService.saveHistory()
                  }
                }
              }

              MouseArea {
                id: notificationMouseArea
                anchors.fill: parent
                anchors.rightMargin: Style.marginLarge * 3 * scaling
                hoverEnabled: true
                // Remove the onClicked handler since we now have a dedicated delete button
              }
            }

            ScrollBar.vertical: ScrollBar {
              active: true
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
            }
          }
        }
      }
    }
  }
}
