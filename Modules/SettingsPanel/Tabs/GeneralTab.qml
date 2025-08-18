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
          text: "General Settings"
          font.pointSize: Style.fontSizeXL * scaling
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
        }

        // Profile section
        ColumnLayout {
          spacing: Style.marginSmall * scaling
          Layout.fillWidth: true
          Layout.topMargin: Style.marginSmall * scaling

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginLarge * scaling

            // Avatar preview
            NImageRounded {
              width: 64 * scaling
              height: 64 * scaling
              imagePath: Settings.data.general.avatarImage
              fallbackIcon: "person"
              borderColor: Color.mPrimary
              borderWidth: Math.max(1, Style.borderMedium)
            }

            NTextInput {
              label: "Profile Picture"
              description: "Your profile picture displayed in various places throughout the shell"
              text: Settings.data.general.avatarImage
              placeholderText: "/home/user/.face"
              Layout.fillWidth: true
              onEditingFinished: {
                Settings.data.general.avatarImage = text
              }
            }
          }
        }
      }

      NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginLarge * 2 * scaling
        Layout.bottomMargin: Style.marginLarge * scaling
      }

      ColumnLayout {
        spacing: Style.marginLarge * scaling
        Layout.fillWidth: true

        NText {
          text: "User Interface"
          font.pointSize: Style.fontSizeXL * scaling
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
          Layout.bottomMargin: Style.marginSmall * scaling
        }

        NToggle {
          label: "Show Corners"
          description: "Display rounded corners on the edge of the screen"
          checked: Settings.data.general.showScreenCorners
          onToggled: checked => {
                       Settings.data.general.showScreenCorners = checked
                     }
        }

        NToggle {
          label: "Dim Desktop"
          description: "Dim the desktop when panels or menus are open"
          checked: Settings.data.general.dimDesktop
          onToggled: checked => {
                       Settings.data.general.dimDesktop = checked
                     }
        }

        NToggle {
          label: "Auto-hide Dock"
          description: "Automatically hide the dock when not in use"
          checked: Settings.data.dock.autoHide
          onToggled: checked => {
                       Settings.data.dock.autoHide = checked
                     }
        }

        ColumnLayout {
          spacing: Style.marginTiniest * scaling
          Layout.fillWidth: true

          NText {
            text: "Border radius"
            font.pointSize: Style.fontSizeLarge * scaling
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
          }

          NText {
            text: "Adjust the rounded border of all UI elements"
            font.pointSize: Style.fontSizeSmall * scaling
            color: Color.mOnSurfaceVariant
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }

          RowLayout {
            NSlider {
              Layout.fillWidth: true
              from: 0
              to: 1
              stepSize: 0.01
              value: Settings.data.general.radiusRatio
              onMoved: Settings.data.general.radiusRatio = value
              cutoutColor: Color.mSurface
            }

            NText {
              text: Math.floor(Settings.data.general.radiusRatio * 100) + "%"
              Layout.alignment: Qt.AlignVCenter
              Layout.leftMargin: Style.marginSmall * scaling
              color: Color.mOnSurface
            }
          }
        }
      }
    }
  }
}
