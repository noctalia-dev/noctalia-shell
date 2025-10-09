import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs.Commons
import qs.Services
import qs.Widgets

// Notification History panel
NPanel {
  id: root

  preferredWidth: 380
  preferredHeight: 480
  panelKeyboardFocus: true

  onOpened: function () {
    Settings.data.notifications.lastSeenTs = Time.timestamp * 1000
  }

  panelContent: Rectangle {
    id: notificationRect
    color: Color.transparent

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL * scaling
      spacing: Style.marginM * scaling

      // Header section
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM * scaling

        NIcon {
          icon: "bell"
          pointSize: Style.fontSizeXXL * scaling
          color: Color.mPrimary
        }

        NText {
          text: I18n.tr("notifications.panel.title")
          pointSize: Style.fontSizeL * scaling
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

      NDivider {
        Layout.fillWidth: true
      }

      // Empty state when no notifications
      ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.alignment: Qt.AlignHCenter
        visible: NotificationService.historyList.count === 0
        spacing: Style.marginL * scaling

        Item {
          Layout.fillHeight: true
        }

        NIcon {
          icon: "bell-off"
          pointSize: 64 * scaling
          color: Color.mOnSurfaceVariant
          Layout.alignment: Qt.AlignHCenter
        }

        NText {
          text: I18n.tr("notifications.panel.no-notifications")
          pointSize: Style.fontSizeL * scaling
          color: Color.mOnSurfaceVariant
          Layout.alignment: Qt.AlignHCenter
        }

        NText {
          text: I18n.tr("notifications.panel.description")
          pointSize: Style.fontSizeS * scaling
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
        spacing: Style.marginM * scaling
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: NotificationService.historyList.count > 0

        // Track which notification is expanded
        property string expandedId: ""

        delegate: Rectangle {
          property string notificationId: model.id
          property bool isExpanded: notificationList.expandedId === notificationId

          width: notificationList.width
          height: notificationLayout.implicitHeight + (Style.marginM * scaling * 2)
          radius: Style.radiusM * scaling
          color: Color.mSurfaceVariant
          border.color: Qt.alpha(Color.mOutline, Style.opacityMedium)
          border.width: Math.max(1, Style.borderS * scaling)

          Behavior on height {
            NumberAnimation {
              duration: Style.animationNormal
              easing.type: Easing.InOutQuad
            }
          }

          // Smooth color transition on hover
          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
            }
          }

          // Click to expand/collapse
          MouseArea {
            anchors.fill: parent
            // Don't capture clicks on the delete button
            anchors.rightMargin: 48 * scaling
            enabled: (summaryText.truncated || bodyText.truncated)
            onClicked: {
              if (notificationList.expandedId === notificationId) {
                notificationList.expandedId = ""
              } else {
                notificationList.expandedId = notificationId
              }
            }
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          }

          RowLayout {
            id: notificationLayout
            anchors.fill: parent
            anchors.margins: Style.marginM * scaling
            spacing: Style.marginM * scaling

            ColumnLayout {
              NImageCircled {
                Layout.preferredWidth: 40 * scaling
                Layout.preferredHeight: 40 * scaling
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 20 * scaling
                imagePath: model.cachedImage || model.originalImage || ""
                borderColor: Color.transparent
                borderWidth: 0
                fallbackIcon: "bell"
                fallbackIconSize: 24 * scaling
              }
              Item {
                Layout.fillHeight: true
              }
            }

            // Notification content column
            ColumnLayout {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignTop
              spacing: Style.marginXS * scaling
              Layout.rightMargin: -(Style.marginM + Style.baseWidgetSize * 0.6) * scaling

              // Header row with app name and timestamp
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS * scaling

                // Urgency indicator
                Rectangle {
                  Layout.preferredWidth: 6 * scaling
                  Layout.preferredHeight: 6 * scaling
                  Layout.alignment: Qt.AlignVCenter
                  radius: 3 * scaling
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
                  pointSize: Style.fontSizeXS * scaling
                  color: Color.mSecondary
                }

                NText {
                  text: Time.formatRelativeTime(model.timestamp)
                  pointSize: Style.fontSizeXS * scaling
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
                pointSize: Style.fontSizeM * scaling
                font.weight: Font.Medium
                color: Color.mOnSurface
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                maximumLineCount: isExpanded ? 999 : 2
                elide: Text.ElideRight
              }

              // Body
              NText {
                id: bodyText
                text: model.body || ""
                pointSize: Style.fontSizeS * scaling
                color: Color.mOnSurfaceVariant
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                maximumLineCount: isExpanded ? 999 : 3
                elide: Text.ElideRight
                visible: text.length > 0
              }

              // Spacer for expand indicator
              Item {
                Layout.fillWidth: true
                Layout.preferredHeight: (!isExpanded && (summaryText.truncated || bodyText.truncated)) ? (Style.marginS * scaling) : 0
              }

              // Expand indicator
              RowLayout {
                Layout.fillWidth: true
                visible: !isExpanded && (summaryText.truncated || bodyText.truncated)
                spacing: Style.marginXS * scaling

                Item {
                  Layout.fillWidth: true
                }

                NText {
                  text: I18n.tr("notifications.panel.click-to-expand") || "Click to expand"
                  pointSize: Style.fontSizeXS * scaling
                  color: Color.mPrimary
                  font.weight: Font.Medium
                }

                NIcon {
                  icon: "chevron-down"
                  pointSize: Style.fontSizeS * scaling
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
