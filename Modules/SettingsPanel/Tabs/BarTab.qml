import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  id: root

  spacing: 0

  ScrollView {
    id: scrollView

    Layout.fillWidth: true
    Layout.fillHeight: true
    padding: Style.marginMedium * scaling
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    ScrollBar.vertical.policy: ScrollBar.AsNeeded

    ColumnLayout {
      width: scrollView.availableWidth
      spacing: 0

      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 0
      }

      ColumnLayout {
        spacing: Style.marginLarge * scaling
        Layout.fillWidth: true

        NText {
          text: "Components"
          font.pointSize: Style.fontSizeXL * scaling
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
        }

        NToggle {
          label: "Show Active Window"
          description: "Display the title of the currently focused window on the left side of the bar"
          checked: Settings.data.bar.showActiveWindow
          onToggled: checked => {
                       Settings.data.bar.showActiveWindow = checked
                     }
        }

        NToggle {
          label: "Show System Info"
          description: "Display system statistics (CPU, RAM, Temperature)"
          checked: Settings.data.bar.showSystemInfo
          onToggled: checked => {
                       Settings.data.bar.showSystemInfo = checked
                     }
        }

        NToggle {
          label: "Show Media"
          description: "Display media controls and information"
          checked: Settings.data.bar.showMedia
          onToggled: checked => {
                       Settings.data.bar.showMedia = checked
                     }
        }

        NToggle {
          label: "Show Notifications History"
          description: "Display a shortcut to the notifications history"
          checked: Settings.data.bar.showNotificationsHistory
          onToggled: checked => {
                       Settings.data.bar.showNotificationsHistory = checked
                     }
        }

        NToggle {
          label: "Show Applications Tray"
          description: "Display the applications tray"
          checked: Settings.data.bar.showTray
          onToggled: checked => {
                       Settings.data.bar.showTray = checked
                     }
        }
      }
    }
  }
}
