import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs.Commons
import qs.Services
import qs.Widgets
import qs.Modules.MainScreen

// Notification History panel
SmartPanel {
  id: root

  preferredWidth: Math.round(340 * Style.uiScaleRatio)
  preferredHeight: Math.round(420 * Style.uiScaleRatio)

  onOpened: function () {
    NotificationService.updateLastSeenTs()
  }

  panelContent: Rectangle {
    id: notificationRect
    color: Color.transparent

    ColumnLayout {
      id: mainColumn
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // Header section
      NBox {
        Layout.fillWidth: true
        implicitHeight: headerRow.implicitHeight + (Style.marginM * 2)

        RowLayout {
          id: headerRow
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          NIcon {
            icon: "bell"
            pointSize: Style.fontSizeXXL
            color: Color.mPrimary
          }

          NText {
            text: I18n.tr("notifications.panel.title")
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
            Layout.fillWidth: true
          }

          NIconButton {
            icon: Settings.data.notifications.doNotDisturb ? "bell-off" : "bell"
            tooltipText: Settings.data.notifications.doNotDisturb ? I18n.tr("tooltips.do-not-disturb-enabled") : I18n.tr("tooltips.do-not-disturb-disabled")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: Settings.data.notifications.doNotDisturb = !Settings.data.notifications.doNotDisturb
          }

          NIconButton {
            icon: "trash"
            tooltipText: I18n.tr("tooltips.clear-history")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: {
              NotificationService.clearHistory()
              // Close panel as there is nothing more to see.
              root.close()
            }
          }

          NIconButton {
            icon: "close"
            tooltipText: I18n.tr("tooltips.close")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: root.close()
          }
        }
      }

      // Empty state when no notifications
      ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.alignment: Qt.AlignHCenter
        visible: NotificationService.historyList.count === 0
        spacing: Style.marginL

        Item {
          Layout.fillHeight: true
        }

        NIcon {
          icon: "bell-off"
          pointSize: 48
          color: Color.mOnSurfaceVariant
          Layout.alignment: Qt.AlignHCenter
        }

        NText {
          text: I18n.tr("notifications.panel.no-notifications")
          pointSize: Style.fontSizeL
          color: Color.mOnSurfaceVariant
          Layout.alignment: Qt.AlignHCenter
        }

        NText {
          text: I18n.tr("notifications.panel.description")
          pointSize: Style.fontSizeS
          color: Color.mOnSurfaceVariant
          Layout.alignment: Qt.AlignHCenter
          Layout.fillWidth: true
          wrapMode: Text.Wrap
          horizontalAlignment: Text.AlignHCenter
        }

        Item {
          Layout.fillHeight: true
        }
      }

      // Notification list
      NListView {
        id: notificationList
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalPolicy: ScrollBar.AlwaysOff
        verticalPolicy: ScrollBar.AsNeeded

        model: NotificationService.historyList
        spacing: Style.marginM
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: NotificationService.historyList.count > 0

        // Track which notification is expanded
        property string expandedId: ""

        delegate: Item {
          property string notificationId: model.id
          property bool isExpanded: notificationList.expandedId === notificationId

          // Cache the content height to break binding loops
          property real contentHeight: notificationLayout.implicitHeight

          // Cache truncation state to avoid binding to truncated property during polish
          property bool hasTextTruncated: false

          width: notificationList.width
          height: contentHeight + (Style.marginM * 2)

          Rectangle {
            anchors.fill: parent
            radius: Style.radiusM
            color: Color.mSurfaceVariant
            border.color: Qt.alpha(Color.mOutline, Style.opacityMedium)
            border.width: Style.borderS

            // Smooth color transition on hover
            Behavior on color {
              enabled: !Settings.data.general.animationDisabled
              ColorAnimation {
                duration: Style.animationFast
              }
            }
          }

          // Click to expand/collapse
          MouseArea {
            anchors.fill: parent
            // Don't capture clicks on the delete button
            anchors.rightMargin: 48
            enabled: hasTextTruncated
            onClicked: {
              if (notificationList.expandedId === notificationId) {
                notificationList.expandedId = ""
              } else {
                notificationList.expandedId = notificationId
              }
            }
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          }

          // Update truncation state asynchronously
          Connections {
            target: summaryText
            function onTruncatedChanged() {
              hasTextTruncated = summaryText.truncated || bodyText.truncated
            }
          }

          Connections {
            target: bodyText
            function onTruncatedChanged() {
              hasTextTruncated = summaryText.truncated || bodyText.truncated
            }
          }

          Component.onCompleted: {
            hasTextTruncated = summaryText.truncated || bodyText.truncated
          }

          Item {
            id: notificationLayoutWrapper
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.marginM
            height: notificationLayout.implicitHeight

            RowLayout {
              id: notificationLayout
              width: parent.width
              spacing: Style.marginM

              // Icon - properly centered vertically
              NImageCircled {
                Layout.preferredWidth: Math.round(40 * Style.uiScaleRatio)
                Layout.preferredHeight: Math.round(40 * Style.uiScaleRatio)
                Layout.alignment: Qt.AlignVCenter
                imagePath: model.cachedImage || model.originalImage || ""
                borderColor: Color.transparent
                borderWidth: 0
                fallbackIcon: "bell"
                fallbackIconSize: 24
              }

              // Notification content column
              ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: Style.marginXS
                Layout.rightMargin: -(Style.marginM + Style.baseWidgetSize * 0.6)

                // Header row with app name and timestamp
                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginS

                  // Urgency indicator
                  Rectangle {
                    Layout.preferredWidth: 6
                    Layout.preferredHeight: 6
                    Layout.alignment: Qt.AlignVCenter
                    radius: 3
                    visible: model.urgency !== 1
                    color: {
                      if (model.urgency === 2)
                        return Color.mError
                      else if (model.urgency === 0)
                        return Color.mOnSurfaceVariant
                      else
                        return Color.transparent
                    }
                  }

                  NText {
                    text: model.appName || "Unknown App"
                    pointSize: Style.fontSizeXS
                    color: Color.mSecondary
                  }

                  NText {
                    text: Time.formatRelativeTime(model.timestamp)
                    pointSize: Style.fontSizeXS
                    color: Color.mSecondary
                  }

                  Item {
                    Layout.fillWidth: true
                  }
                }

                // Summary
                NText {
                  id: summaryText
                  text: model.summary || I18n.tr("general.no-summary")
                  pointSize: Style.fontSizeM
                  font.weight: Font.Medium
                  color: Color.mOnSurface
                  textFormat: Text.PlainText
                  wrapMode: Text.Wrap
                  Layout.fillWidth: true
                  maximumLineCount: isExpanded ? 999 : 2
                  elide: Text.ElideRight

                  // Smooth transition without triggering layout recalculation
                  Behavior on maximumLineCount {
                    enabled: false // Disable animation on this to avoid polish loops
                  }
                }

                // Body
                NText {
                  id: bodyText
                  text: model.body || ""
                  pointSize: Style.fontSizeS
                  color: Color.mOnSurfaceVariant
                  textFormat: Text.PlainText
                  wrapMode: Text.Wrap
                  Layout.fillWidth: true
                  maximumLineCount: isExpanded ? 999 : 3
                  elide: Text.ElideRight
                  visible: text.length > 0

                  // Smooth transition without triggering layout recalculation
                  Behavior on maximumLineCount {
                    enabled: false // Disable animation on this to avoid polish loops
                  }
                }

                // Spacer for expand indicator
                Item {
                  Layout.fillWidth: true
                  Layout.preferredHeight: Style.marginS
                  visible: !isExpanded && hasTextTruncated
                }

                // Expand indicator
                RowLayout {
                  Layout.fillWidth: true
                  visible: !isExpanded && hasTextTruncated
                  spacing: Style.marginXS

                  Item {
                    Layout.fillWidth: true
                  }

                  NText {
                    text: I18n.tr("notifications.panel.click-to-expand") || "Click to expand"
                    pointSize: Style.fontSizeXS
                    color: Color.mPrimary
                    font.weight: Font.Medium
                  }

                  NIcon {
                    icon: "chevron-down"
                    pointSize: Style.fontSizeS
                    color: Color.mPrimary
                  }
                }
              }

              // Delete button
              NIconButton {
                icon: "trash"
                tooltipText: I18n.tr("tooltips.delete-notification")
                baseSize: Style.baseWidgetSize * 0.7
                Layout.alignment: Qt.AlignTop

                onClicked: {
                  // Remove from history using the service API
                  NotificationService.removeFromHistory(notificationId)
                }
              }
            }
          }
        }
      }
    }
  }
}
