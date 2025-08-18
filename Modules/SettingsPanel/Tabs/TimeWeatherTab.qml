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
        spacing: Style.marginTiny * scaling
        Layout.fillWidth: true

        NText {
          text: "Location"
          font.pointSize: Style.fontSizeXL * scaling
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
          Layout.bottomMargin: Style.marginSmall * scaling
        }

        // Location section
        ColumnLayout {
          spacing: Style.marginMedium * scaling
          Layout.fillWidth: true
          Layout.topMargin: Style.marginSmall * scaling

          NTextInput {
            label: "Location name"
            description: "Choose a known location near you"
            text: Settings.data.location.name
            enabled: !Settings.data.location.autoLocation
            placeholderText: "Enter the location name"
            Layout.fillWidth: true
            onEditingFinished: {
              Settings.data.location.name = text
              LocationService.resetWeather()
            }
          }
        }

        NDivider {
          Layout.fillWidth: true
          Layout.topMargin: Style.marginLarge * 2 * scaling
          Layout.bottomMargin: Style.marginLarge * scaling
        }

        // Time section
        ColumnLayout {
          spacing: Style.marginLarge * scaling
          Layout.fillWidth: true

          NText {
            text: "Time Format"
            font.pointSize: Style.fontSizeXL * scaling
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
            Layout.bottomMargin: Style.marginSmall * scaling
          }

          NToggle {
            label: "Use 12-Hour Clock"
            description: "Display time in 12-hour format (AM/PM) instead of 24-hour"
            checked: Settings.data.location.use12HourClock
            onToggled: checked => {
                         Settings.data.location.use12HourClock = checked
                       }
          }

          NToggle {
            label: "Reverse Day/Month"
            description: "Display date as DD/MM instead of MM/DD"
            checked: Settings.data.location.reverseDayMonth
            onToggled: checked => {
                         Settings.data.location.reverseDayMonth = checked
                       }
          }

          NToggle {
            label: "Show Date with Clock"
            description: "Display date alongside time (e.g., 18:12 - Sat, 23 Aug)"
            checked: Settings.data.location.showDateWithClock
            onToggled: checked => {
                         Settings.data.location.showDateWithClock = checked
                       }
          }
        }

        NDivider {
          Layout.fillWidth: true
          Layout.topMargin: Style.marginLarge * 2 * scaling
          Layout.bottomMargin: Style.marginLarge * scaling
        }

        // Weather section
        ColumnLayout {
          spacing: Style.marginMedium * scaling
          Layout.fillWidth: true

          NText {
            text: "Weather"
            font.pointSize: Style.fontSizeXL * scaling
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
            Layout.bottomMargin: Style.marginSmall * scaling
          }

          NToggle {
            label: "Use Fahrenheit"
            description: "Display temperature in Fahrenheit instead of Celsius"
            checked: Settings.data.location.useFahrenheit
            onToggled: checked => {
                         Settings.data.location.useFahrenheit = checked
                       }
          }
          NToggle {
            label: "Detect Auto Location"
            description: "Detect Location based on IP"
            checked: Settings.data.location.autoLocation
            onToggled: checked => {
              Settings.data.location.autoLocation = checked
            }
          }
        }
      }
    }
  }
}
